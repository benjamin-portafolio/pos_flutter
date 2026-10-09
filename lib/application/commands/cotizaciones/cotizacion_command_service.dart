import 'dart:convert';
import '../../../domain/ventas/sale_status.dart';
import '../../sync/payloads/cotizacion_recuperada_payload.dart';
import '../../sync/quotation_recovery_validator.dart';
import 'recuperar_cotizacion_command.dart';
import 'recuperar_cotizacion_result.dart';
import 'quotation_recovery_identity.dart';
import '../../sync/payloads/cotizacion_recovery_line_identity.dart';
import '../../sync/payloads/quotation_selection_snapshot.dart';
import '../../sync/payloads/producto_agregado_borrador_payload.dart';
import '../../sync/payloads/inventory_movement_payload.dart';
import '../../sync/projections/quotation_projection.dart';
import '../../sync/local_event_store.dart';
import '../../sync/models/sync_event.dart';
import '../../sync/payloads/cotizacion_guardada_line.dart';
import '../../sync/payloads/cotizacion_guardada_payload.dart';
import '../../sync/payloads/sale_item_snapshot.dart';
import '../../sync/projections/quotation_projection_store.dart';
import '../../sync/projections/sale_draft_projection_store.dart';
import '../../sync/quotation_draft_validator.dart';
import '../local_command_context.dart';
import 'guardar_cotizacion_command.dart';
import 'guardar_cotizacion_result.dart';
import 'quotation_already_linked_exception.dart';

class CotizacionCommandService {
  CotizacionCommandService({
    required this.store,
    required this.drafts,
    required this.events,
    required this.context,
    required this.validator,
  });
  final QuotationProjectionStore store;
  final SaleDraftProjectionStore drafts;
  final LocalEventStore events;
  final LocalCommandContext context;
  final QuotationRecoveryValidator validator;

  Future<GuardarCotizacionResult> guardar(GuardarCotizacionCommand command) =>
      store.atomic(() async {
        _validateIntent(command);
        final previous = await store.findEventById(command.eventId);
        if (previous != null) return _retry(command, previous);
        if (await store.findById(command.quotationId) != null) {
          throw StateError(
            'La identidad de cotización ya pertenece a otra intención.',
          );
        }
        final sale = await drafts.findById(command.saleId);
        final lines = QuotationDraftValidator.validate(
          sale: sale,
          userId: context.userId,
          deviceId: context.deviceId,
          expectedDraftEventId: command.expectedDraftEventId,
          items: await drafts.items(command.saleId),
        );
        final linked = await store.findByCurrentSaleId(command.saleId);
        if (linked != null) throw QuotationAlreadyLinkedException(linked.id);
        final payload = CotizacionGuardadaPayload(
          sourceSaleId: sale!.id,
          sourceDraftEventId: sale.lastEventId!,
          issuedAtMs: command.issuedAtLocal.millisecondsSinceEpoch,
          lines: [
            for (final line in lines)
              CotizacionGuardadaLine(
                id: CotizacionGuardadaLine.idFor(command.quotationId, line.id),
                sourceSaleItemId: line.id,
                sortOrder: line.sortOrder,
                selection: QuotationSelectionSnapshot.fromSale(line.snapshot),
              ),
          ],
        );
        final refs = payload.refs(
          command.quotationId,
        ); // Validadas en ambos modos.
        await events.appendAndApply(
          SyncEvent(
            eventId: command.eventId,
            aggregateType: CotizacionGuardadaPayload.aggregateType,
            aggregateId: command.quotationId,
            eventType: CotizacionGuardadaPayload.eventType,
            deviceId: context.deviceId,
            userId: context.userId,
            baseVersion: 0,
            createdAtLocal: command.issuedAtLocal,
            deliveryStatus: 'not_required',
            payload: payload.toJson(),
          ),
          refs: refs,
        );
        return GuardarCotizacionResult(
          quotationId: command.quotationId,
          eventId: command.eventId,
          issuedAtLocal: command.issuedAtLocal,
        );
      });

  Future<RecuperarCotizacionResult> recuperar(
    RecuperarCotizacionCommand command,
  ) => store.atomic(() async {
    if ([
          context.userId,
          context.deviceId,
          command.quotationId,
          command.expectedQuotationEventId,
          command.saleId,
          command.eventId,
        ].any((id) => id.trim().isEmpty) ||
        command.saleId == command.quotationId ||
        command.eventId == command.expectedQuotationEventId ||
        command.recoveredAtLocal.millisecondsSinceEpoch <= 0 ||
        command.recoveredAtLocal.millisecondsSinceEpoch >
            SaleItemSnapshot.maxInteger) {
      throw const FormatException('Intención inválida.');
    }
    InventoryMovementPayload.requiredUuidV4(command.saleId, 'sale_id');
    InventoryMovementPayload.requiredUuidV4(command.eventId, 'event_id');
    final quotation = await store.findById(command.quotationId);
    if (quotation == null ||
        !quotation.active ||
        quotation.userId != context.userId ||
        quotation.deviceId != context.deviceId) {
      throw StateError('La cotización no pertenece al contexto actual.');
    }
    final linked = quotation.currentSaleId == null
        ? null
        : await drafts.findById(quotation.currentSaleId!);
    if (linked != null &&
        (linked.userId != context.userId ||
            linked.deviceId != context.deviceId)) {
      throw StateError('El vínculo pertenece a otro propietario.');
    }
    if (linked?.status == SaleStatus.confirmada) {
      throw StateError('La cotización ya fue vendida.');
    }
    final previous = await store.findEventById(command.eventId);
    if (previous != null) {
      final payload = await _validRecoveryEvent(previous, quotation);
      if (payload.saleId != command.saleId ||
          payload.baseQuotationEventId != command.expectedQuotationEventId ||
          payload.recoveredAtMs !=
              command.recoveredAtLocal.millisecondsSinceEpoch) {
        throw StateError('La intención recuperada tiene otro contenido.');
      }
      return _recoveryResult(
        payload,
        previous.eventId,
        continued: true,
        draftAvailable:
            linked?.id == payload.saleId &&
            linked!.active &&
            linked.status == SaleStatus.borrador,
      );
    }
    CotizacionRecuperadaPayload? currentPayload;
    SyncEvent? currentEvent;
    if (linked != null &&
        linked.active &&
        linked.status == SaleStatus.borrador &&
        quotation.lastEventId != null) {
      currentEvent = await store.findEventById(quotation.lastEventId!);
      if (currentEvent?.eventType == CotizacionRecuperadaPayload.eventType) {
        currentPayload = await _validRecoveryEvent(currentEvent!, quotation);
        if (currentPayload.saleId != linked.id ||
            currentPayload.draftCreatedEventId != linked.createdEventId ||
            currentEvent.baseVersion != quotation.version - 1) {
          throw StateError('El vínculo no acredita esta captura.');
        }
      }
    }
    final sameRevision =
        quotation.lastEventId == command.expectedQuotationEventId ||
        currentPayload?.baseQuotationEventId ==
            command.expectedQuotationEventId;
    if (!sameRevision) throw StateError('La revisión de la cotización cambió.');
    if (linked != null &&
        linked.active &&
        linked.status == SaleStatus.borrador) {
      if (currentPayload != null) {
        return _recoveryResult(
          currentPayload,
          currentEvent!.eventId,
          continued: true,
          draftAvailable: true,
        );
      }
      return RecuperarCotizacionResult(
        saleId: linked.id,
        eventId: null,
        continued: true,
        draftAvailable: true,
      );
    }
    if (await drafts.findDraft(context.userId, context.deviceId) != null) {
      throw StateError(
        'Resuelve la otra captura de Caja antes de recuperar esta cotización.',
      );
    }
    if (quotation.version < 1 ||
        quotation.version >= SaleItemSnapshot.maxInteger ||
        command.saleId == quotation.sourceSaleId ||
        await drafts.wasCleared(command.saleId) ||
        await drafts.findById(command.saleId) != null ||
        (await drafts.items(command.saleId)).isNotEmpty) {
      throw StateError(
        'La identidad de venta ya fue usada o la revisión no es válida.',
      );
    }
    final selection = await store.items(quotation.id);
    final prepared = await validator.prepare(items: selection);
    final identities = [
      for (final l in prepared)
        CotizacionRecoveryLineIdentity(
          quotationItemId: l.quotationItemId,
          saleItemId: QuotationRecoveryIdentity.saleItem(
            command.saleId,
            l.quotationItemId,
          ),
          draftEventId: QuotationRecoveryIdentity.draftEvent(
            command.eventId,
            command.saleId,
            l.quotationItemId,
          ),
          sortOrder: l.sortOrder,
        ),
    ];
    for (final l in identities) {
      if (await store.containsSaleItem(l.saleItemId) ||
          await store.findEventById(l.draftEventId) != null) {
        throw StateError('La identidad de línea o evento ya fue usada.');
      }
    }
    final payload = CotizacionRecuperadaPayload(
      baseQuotationEventId: quotation.lastEventId!,
      previousSaleId: quotation.currentSaleId,
      saleId: command.saleId,
      recoveredAtMs: command.recoveredAtLocal.millisecondsSinceEpoch,
      draftVersion: identities.length,
      draftCreatedEventId: identities.first.draftEventId,
      draftLastEventId: identities.last.draftEventId,
      lines: identities,
    );
    payload.validateIdentity(command.eventId);
    final entries = <LocalEventAppend>[
      for (var i = 0; i < prepared.length; i++)
        LocalEventAppend(
          event: SyncEvent(
            eventId: identities[i].draftEventId,
            aggregateType: ProductoAgregadoBorradorPayload.aggregateType,
            aggregateId: command.saleId,
            eventType: ProductoAgregadoBorradorPayload.eventType,
            userId: context.userId,
            deviceId: context.deviceId,
            baseVersion: i,
            createdAtLocal: command.recoveredAtLocal,
            deliveryStatus: 'not_required',
            payload: ProductoAgregadoBorradorPayload(
              saleItemId: identities[i].saleItemId,
              sortOrder: prepared[i].sortOrder,
              item: prepared[i].snapshot,
            ).toJson(),
          ),
          refs: prepared[i].refs(command.saleId, identities[i].saleItemId),
        ),
      LocalEventAppend(
        event: SyncEvent(
          eventId: command.eventId,
          aggregateType: CotizacionRecuperadaPayload.aggregateType,
          aggregateId: quotation.id,
          eventType: CotizacionRecuperadaPayload.eventType,
          userId: context.userId,
          deviceId: context.deviceId,
          baseVersion: quotation.version,
          createdAtLocal: command.recoveredAtLocal,
          deliveryStatus: 'not_required',
          payload: payload.toJson(),
        ),
        refs: payload.refs(quotation.id),
      ),
    ];
    // La transacción exterior incluye lecturas, todos los eventos/refs y el vínculo.
    for (final entry in entries) {
      await events.appendAndApply(entry.event, refs: entry.refs);
    }
    return _recoveryResult(
      payload,
      command.eventId,
      continued: false,
      draftAvailable: true,
    );
  });

  Future<CotizacionRecuperadaPayload> _validRecoveryEvent(
    SyncEvent event,
    QuotationProjection quotation,
  ) async {
    if (event.aggregateType != CotizacionRecuperadaPayload.aggregateType ||
        event.eventType != CotizacionRecuperadaPayload.eventType ||
        event.aggregateId != quotation.id ||
        event.userId != context.userId ||
        event.deviceId != context.deviceId ||
        event.baseVersion == null ||
        event.baseVersion! < 1 ||
        event.baseVersion! >= quotation.version ||
        event.applicationStatus != 'applied' ||
        event.deliveryStatus != 'not_required' ||
        event.serverSequence != null ||
        event.baseServerSequence != null ||
        event.createdAtServer != null) {
      throw StateError('La identidad del evento ya tiene otro contenido.');
    }
    final payload = CotizacionRecuperadaPayload.fromJson(event.payload);
    payload.validateIdentity(event.eventId);
    payload.refs(quotation.id);
    final items = await store.items(quotation.id);
    if (payload.recoveredAtMs != event.createdAtLocal.millisecondsSinceEpoch ||
        payload.lines.length != items.length ||
        payload.lines.any(
          (line) => !items.any(
            (item) =>
                item.id == line.quotationItemId &&
                item.sortOrder == line.sortOrder,
          ),
        )) {
      throw StateError('La intención recuperada tiene otro contenido.');
    }
    final base = await store.findEventById(payload.baseQuotationEventId);
    if (base == null ||
        base.aggregateType != 'quotation' ||
        base.aggregateId != quotation.id ||
        (base.baseVersion ?? -1) + 1 != event.baseVersion ||
        base.userId != event.userId ||
        base.deviceId != event.deviceId) {
      throw StateError('La revisión base no acredita la recuperación.');
    }
    final previousSaleId = switch (base.eventType) {
      CotizacionGuardadaPayload.eventType => CotizacionGuardadaPayload.fromJson(
        base.payload,
      ).sourceSaleId,
      CotizacionRecuperadaPayload.eventType =>
        CotizacionRecuperadaPayload.fromJson(base.payload).saleId,
      _ => throw StateError('La revisión base no es de cotización.'),
    };
    if (payload.previousSaleId != previousSaleId) {
      throw StateError('El vínculo anterior tiene otro contenido.');
    }
    return payload;
  }

  RecuperarCotizacionResult _recoveryResult(
    CotizacionRecuperadaPayload payload,
    String eventId, {
    required bool continued,
    required bool draftAvailable,
  }) => RecuperarCotizacionResult(
    saleId: payload.saleId,
    eventId: eventId,
    continued: continued,
    draftAvailable: draftAvailable,
  );

  void _validateIntent(GuardarCotizacionCommand command) {
    if ([
          context.userId,
          context.deviceId,
          command.saleId,
          command.expectedDraftEventId,
          command.quotationId,
          command.eventId,
        ].any((id) => id.trim().isEmpty) ||
        command.quotationId == command.saleId ||
        command.eventId == command.expectedDraftEventId ||
        command.issuedAtLocal.millisecondsSinceEpoch <= 0 ||
        command.issuedAtLocal.millisecondsSinceEpoch >
            SaleItemSnapshot.maxInteger) {
      throw const FormatException(
        'Intención de cotización o contexto inválidos.',
      );
    }
  }

  Future<GuardarCotizacionResult> _retry(
    GuardarCotizacionCommand command,
    SyncEvent event,
  ) async {
    if (event.aggregateType != CotizacionGuardadaPayload.aggregateType ||
        event.eventType != CotizacionGuardadaPayload.eventType ||
        event.aggregateId != command.quotationId ||
        event.userId != context.userId ||
        event.deviceId != context.deviceId ||
        event.applicationStatus != 'applied' ||
        event.baseVersion != 0 ||
        event.serverSequence != null ||
        event.baseServerSequence != null ||
        event.createdAtServer != null ||
        event.createdAtLocal.millisecondsSinceEpoch !=
            command.issuedAtLocal.millisecondsSinceEpoch ||
        event.deliveryStatus != 'not_required') {
      throw StateError('La identidad del evento ya tiene otro contenido.');
    }
    final payload = CotizacionGuardadaPayload.fromJson(event.payload);
    payload.refs(command.quotationId);
    final quotation = await store.findById(command.quotationId);
    if (payload.sourceSaleId != command.saleId ||
        payload.sourceDraftEventId != command.expectedDraftEventId ||
        payload.issuedAtMs != command.issuedAtLocal.millisecondsSinceEpoch ||
        quotation == null ||
        quotation.createdEventId != event.eventId ||
        quotation.userId != event.userId ||
        quotation.deviceId != event.deviceId ||
        quotation.sourceSaleId != payload.sourceSaleId ||
        quotation.sourceDraftEventId != payload.sourceDraftEventId ||
        quotation.issuedAtLocal.millisecondsSinceEpoch != payload.issuedAtMs) {
      throw StateError('La intención guardada tiene otro contenido.');
    }
    final items = await store.items(quotation.id);
    if (items.length != payload.lines.length ||
        payload.lines.any(
          (line) => !items.any(
            (item) =>
                item.id == line.id &&
                item.sortOrder == line.sortOrder &&
                jsonEncode(item.selection.toJson()) ==
                    jsonEncode(line.selection.toJson()),
          ),
        )) {
      throw StateError('La selección guardada tiene otro contenido.');
    }
    return GuardarCotizacionResult(
      quotationId: quotation.id,
      eventId: event.eventId,
      issuedAtLocal: quotation.issuedAtLocal,
    );
  }
}
