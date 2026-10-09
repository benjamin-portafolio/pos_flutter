import 'dart:async';

import 'package:pos_flutter/application/commands/cotizaciones/cotizacion_command_service.dart';
import 'package:pos_flutter/application/commands/cotizaciones/guardar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/cotizaciones/guardar_cotizacion_result.dart';
import 'package:pos_flutter/application/commands/cotizaciones/recuperar_cotizacion_command.dart';
import 'package:pos_flutter/application/commands/cotizaciones/recuperar_cotizacion_result.dart';
import 'package:pos_flutter/application/commands/ventas/limpiar_venta_borrador_command.dart';
import 'package:pos_flutter/application/commands/ventas/venta_borrador_command_service.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_estimate.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_line_estimate.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_item.dart';
import 'package:pos_flutter/domain/cotizaciones/quotation_status.dart';
import 'package:pos_flutter/domain/repositories/quotation_repository.dart';

Quotation sampleQuotation({
  String id = 'quotation-1',
  QuotationStatus status = QuotationStatus.disponible,
  DateTime? date,
  List<QuotationItem>? items,
}) => Quotation(
  id: id,
  userId: 'user',
  deviceId: 'device',
  issuedAtLocal: date ?? DateTime(2026, 10, 5, 9, 30),
  sourceSaleId: 'sale',
  sourceDraftEventId: 'draft-event',
  currentSaleId: status == QuotationStatus.disponible ? null : 'linked-sale',
  status: status,
  lastEventId: 'quotation-event',
  items: items ?? quotationLines,
);

const quotationLines = [
  QuotationItem(
    id: 'piece-line',
    sortOrder: 0,
    variantId: 'piece',
    productName: 'Pan artesanal',
    variantName: 'Integral',
    saleMode: 'unit',
    quantity: 2,
    measuredQuantityAtomic: null,
    unitCode: null,
    unitSymbol: null,
    unitAtomicFactor: null,
  ),
  QuotationItem(
    id: 'measured-line',
    sortOrder: 1,
    variantId: 'measured',
    productName:
        'Café de especialidad de la sierra con nombre largo para verificar el ticket completo',
    variantName: 'Tueste medio, selección de origen',
    saleMode: 'measured',
    quantity: null,
    measuredQuantityAtomic: 750,
    unitCode: 'kg',
    unitSymbol: 'kg',
    unitAtomicFactor: 1000,
  ),
  QuotationItem(
    id: 'liquid-line',
    sortOrder: 2,
    variantId: 'liquid',
    productName: 'Leche de almendra',
    variantName: null,
    saleMode: 'measured',
    quantity: null,
    measuredQuantityAtomic: 250,
    unitCode: 'l',
    unitSymbol: 'L',
    unitAtomicFactor: 1000,
  ),
];

QuotationEstimate sampleEstimate(
  Quotation quotation, {
  int piecePriceMinor = 3500,
  DateTime? calculatedAt,
}) {
  final lines = [
    for (final item in quotation.items)
      QuotationLineEstimate(
        quotationItemId: item.id,
        unitPriceMinor: item.saleMode == 'unit'
            ? piecePriceMinor
            : item.unitCode == 'kg'
            ? 20000
            : 10000,
        priceReferenceQuantityAtomic: item.saleMode == 'unit' ? null : 1000,
        totalMinor: item.saleMode == 'unit'
            ? item.quantity! * piecePriceMinor
            : item.measuredQuantityAtomic! * (item.unitCode == 'kg' ? 20 : 10),
      ),
  ];
  return QuotationEstimate(
    calculatedAt: calculatedAt ?? DateTime.utc(2026, 10, 6, 18),
    totalMinor: lines.fold<int>(0, (sum, l) => sum + l.totalMinor!),
    lines: lines,
  );
}

class FakeQuotationRepository implements QuotationRepository {
  FakeQuotationRepository([List<Quotation>? initial])
    : documents = initial ?? [sampleQuotation()];
  List<Quotation> documents;
  Stream<List<Quotation>> Function(bool)? listSource;
  Stream<Quotation?> Function(String)? documentSource;
  final filters = <bool>[];
  final reads = <String>[];
  Future<QuotationEstimate> Function(Quotation)? estimateSource;

  @override
  Stream<List<Quotation>> watchQuotations({bool onlyRecoverable = true}) {
    filters.add(onlyRecoverable);
    return listSource?.call(onlyRecoverable) ??
        Stream.value(
          documents
              .where(
                (q) => !onlyRecoverable || q.status != QuotationStatus.vendida,
              )
              .toList()
            ..sort((a, b) => b.issuedAtLocal.compareTo(a.issuedAtLocal)),
        );
  }

  @override
  Stream<Quotation?> watchById(String quotationId) {
    reads.add(quotationId);
    return documentSource?.call(quotationId) ??
        Stream.value(documents.where((q) => q.id == quotationId).firstOrNull);
  }

  @override
  Future<QuotationEstimate> estimate(Quotation quotation) async =>
      estimateSource?.call(quotation) ?? sampleEstimate(quotation);

  @override
  Future<Quotation?> findById(String quotationId) async =>
      documents.where((q) => q.id == quotationId).firstOrNull;
}

class FakeQuotationCommands implements CotizacionCommandService {
  final saved = <GuardarCotizacionCommand>[];
  final recovered = <RecuperarCotizacionCommand>[];
  Future<void>? gate;
  Object? error;
  RecuperarCotizacionResult result = RecuperarCotizacionResult(
    saleId: 'recovered-sale',
    eventId: 'recovery-event',
    continued: false,
    draftAvailable: true,
  );

  @override
  Future<GuardarCotizacionResult> guardar(
    GuardarCotizacionCommand command,
  ) async {
    saved.add(command);
    await gate;
    if (error case final error?) throw error;
    return GuardarCotizacionResult(
      quotationId: 'quotation-1',
      eventId: command.eventId,
      issuedAtLocal: command.issuedAtLocal,
    );
  }

  @override
  Future<RecuperarCotizacionResult> recuperar(
    RecuperarCotizacionCommand command,
  ) async {
    recovered.add(command);
    await gate;
    if (error case final error?) throw error;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeQuotationDraftCommands implements VentaBorradorCommandService {
  final cleared = <LimpiarVentaBorradorCommand>[];
  Future<void>? gate;
  Object? error;
  @override
  Future<void> limpiar(LimpiarVentaBorradorCommand command) async {
    cleared.add(command);
    await gate;
    if (error case final error?) throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
