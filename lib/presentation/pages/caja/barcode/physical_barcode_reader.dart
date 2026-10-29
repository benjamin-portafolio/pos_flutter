import 'dart:async';
import 'dart:ui' show ViewFocusEvent, ViewFocusState;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../../application/commands/articulos/asignar_codigo_barras_variante_command.dart';
import '../../../../application/commands/articulos/crear_articulo_command.dart';
import '../../../../application/commands/articulos/producto_command_service.dart';
import '../../../../core/di/injection.dart';
import '../../gestion_inventario/articulos/barcode_article_creation_flow.dart';
import '../../../../domain/articulos/variante_por_codigo_barras.dart';
import '../../../../domain/repositories/producto_repository.dart';
import '../../../../domain/repositories/sale_draft_repository.dart';
import '../../articulos/sale_quantity_form_result.dart';
import '../weighing/sale_measured_quantity_dialog.dart';
import 'barcode_product_selection_dialog.dart';
import 'physical_barcode_finish_dialog.dart';
import 'physical_barcode_read_admission.dart';
import 'physical_barcode_reader_controller.dart';
import 'sale_barcode_assigned_exception.dart';
import 'sale_barcode_assignment_flow.dart';
import 'sale_barcode_read_coordinator.dart';
import 'sale_barcode_read_outcome.dart';
import 'sale_barcode_read_result.dart';

/// Campo HID de Caja. La cola y sus comandos pertenecen al controlador;
/// este widget coordina únicamente captura, foco, diálogos y ciclo de vida.
class PhysicalBarcodeReader extends StatefulWidget {
  const PhysicalBarcodeReader({
    required this.coordinator,
    required this.saleDraftRepository,
    required this.productoRepository,
    required this.assignBarcode,
    this.createArticle,
    this.onOpenSearch,
    this.onScanBarcode,
    this.onQueryChanged,
    this.shouldSubmit,
    this.onAdded,
    this.onCharge,
    this.onBack,
    this.initialText = '',
    this.searchMode = false,
    this.interactionEnabled = true,
    super.key,
  });

  final SaleBarcodeReadCoordinator coordinator;
  final SaleDraftRepository saleDraftRepository;
  final ProductoRepository productoRepository;
  final Future<void> Function(AsignarCodigoBarrasVarianteCommand) assignBarcode;
  final Future<void> Function(CrearArticuloCommand)? createArticle;
  final void Function(String)? onOpenSearch;
  final VoidCallback? onScanBarcode;
  final ValueChanged<String>? onQueryChanged;
  final bool Function(String)? shouldSubmit;
  final VoidCallback? onAdded;

  /// Enter con el campo vacío solicita cobrar; con texto sigue siendo una
  /// lectura del lector de códigos.
  final VoidCallback? onCharge;
  final VoidCallback? onBack;
  final String initialText;
  final bool searchMode;
  final bool interactionEnabled;

  @override
  PhysicalBarcodeReaderState createState() => PhysicalBarcodeReaderState();
}

class PhysicalBarcodeReaderState extends State<PhysicalBarcodeReader>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _focus = FocusNode(
    debugLabel: 'Lector físico',
    // Una repetición del terminador del lector no es una nueva intención
    // de cobrar cuando el código ya se ha retirado del campo.
    onKeyEvent: (_, event) =>
        event is KeyRepeatEvent &&
            (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter)
        ? KeyEventResult.handled
        : KeyEventResult.ignored,
  );
  PhysicalBarcodeReaderController? _session;
  SaleBarcodeReadResult? _shownResult;
  Future<void>? _finishOperation;
  Completer<void>? _readerDialogClosed;
  int _ownDialogDepth = 0;
  int _interruptionGeneration = 0;
  bool _routeVisible = true;
  bool _appActive = true;
  bool _windowFocused = true;
  bool _closing = false;
  bool _requiresExplicitResume = false;
  bool _preparationRequested = false;
  int? _restoringGeneration;
  bool _manualKeyboard = false;
  String? _notice;

  bool get isEnabled => _session != null;
  int get interruptionGeneration => _interruptionGeneration;
  bool get _available => _routeVisible && _appActive && _windowFocused;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appActive =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _requiresExplicitResume = !_appActive;
    _manualKeyboard = widget.searchMode;
    _text.text = widget.initialText;
    _text.addListener(_queryChanged);
    _focus.addListener(_focusChanged);
    _preparationRequested = true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeVisible = ModalRoute.isCurrentOf(context) ?? true;
    if (!_routeVisible && _ownDialogDepth == 0 && _session != null) {
      // Rutas ajenas requieren reanudación explícita al regresar.
      _interruptionGeneration++;
      _requiresExplicitResume = true;
      pause();
    }
    _schedulePreparation();
  }

  @override
  void didUpdateWidget(PhysicalBarcodeReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interactionEnabled) _schedulePreparation();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (!_appActive) _interrupt();
    _schedulePreparation();
    if (mounted) setState(() {});
  }

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.viewId != View.of(context).viewId) return;
    _windowFocused = event.state == ViewFocusState.focused;
    if (!_windowFocused) _interrupt();
    _schedulePreparation();
    if (mounted) setState(() {});
  }

  void _interrupt() {
    _interruptionGeneration++;
    _requiresExplicitResume = true;
    _manualKeyboard = false;
    pause();
  }

  void clearInput() => _text.clear();

  void pause() {
    if (!widget.searchMode) _text.clear();
    _session?.pause();
  }

  void enableReader({int? restoringGeneration}) {
    if (!mounted || _closing || _session != null) return;
    _preparationRequested = true;
    _restoringGeneration = restoringGeneration;
    // La activación manual es explícita. Las restauraciones deben
    // conservar cualquier interrupción ocurrida durante la ruta anterior.
    if (restoringGeneration == null) _requiresExplicitResume = false;
    _schedulePreparation();
  }

  void _schedulePreparation() {
    if (!_preparationRequested) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_preparationRequested ||
          _session != null ||
          _closing ||
          _finishOperation != null ||
          !widget.interactionEnabled ||
          !_available) {
        return;
      }
      _preparationRequested = false;
      _startSession();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _startSession() {
    final session = PhysicalBarcodeReaderController(
      coordinator: widget.coordinator,
      selectProduct: (candidates) => _showReaderDialog<VariantePorCodigoBarras>(
        (_) => BarcodeProductSelectionDialog(candidates: candidates),
      ),
      requestQuantity: (candidate) => _showReaderDialog<SaleQuantityFormResult>(
        (_) => SaleMeasuredQuantityDialog(
          allowWeighing: true,
          loadConditions: () =>
              widget.coordinator.conditionsFor(candidate.varianteId),
          watchDraft: widget.saleDraftRepository.watchCurrentDraft,
        ),
      ),
      assignUnknownCode: (code, canContinue) => _showReaderInteraction(
        () => SaleBarcodeAssignmentFlow(
          repository: widget.productoRepository,
          assign: widget.assignBarcode,
          createArticle: (context, code, canContinue) =>
              BarcodeArticleCreationFlow(
                create:
                    widget.createArticle ??
                    getIt<ProductoCommandService>().crearArticulo,
              ).run(context, code, canContinue: canContinue),
        ).run(context, code, canContinue: canContinue),
      ),
    );
    _session = session;
    _shownResult = null;
    _notice = null;
    _requiresExplicitResume =
        _requiresExplicitResume ||
        (_restoringGeneration != null &&
            _restoringGeneration != _interruptionGeneration);
    _restoringGeneration = null;
    session.addListener(_changed);
    session.activate();
    if (_requiresExplicitResume) session.pause();
    if (!_requiresExplicitResume) {
      _requestFocus(session);
    }
    setState(() {});
  }

  void _requestFocus(PhysicalBarcodeReaderController session) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          identical(_session, session) &&
          !_closing &&
          widget.interactionEnabled &&
          !_requiresExplicitResume &&
          session.isAccepting &&
          _available) {
        _focus.requestFocus();
      }
    });
  }

  void _resume() {
    if (!_available || _closing || !widget.interactionEnabled) return;
    if (!widget.searchMode &&
        (_requiresExplicitResume || _session?.isPaused == true)) {
      _text.clear();
    }
    _requiresExplicitResume = false;
    _session?.resume();
    _focus.requestFocus();
  }

  void _toggleManualKeyboard() {
    final session = _session;
    if (session == null ||
        !_available ||
        _closing ||
        !widget.interactionEnabled) {
      return;
    }
    final showKeyboard = !_manualKeyboard;
    final generation = _interruptionGeneration;
    _focus.unfocus();
    setState(() => _manualKeyboard = showKeyboard);
    // Reconectar después de actualizar keyboardType también permite abrir el
    // teclado si el campo ya tenía foco. No afecta a otros campos de la app.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          identical(_session, session) &&
          generation == _interruptionGeneration) {
        _resume();
      }
    });
  }

  void _focusChanged() {
    final session = _session;
    if (session == null || _closing || _ownDialogDepth > 0) return;
    if (!_focus.hasFocus) {
      pause();
    } else if (_available && !_requiresExplicitResume) {
      session.resume();
    }
    if (mounted) setState(() {});
  }

  void _queryChanged() => widget.onQueryChanged?.call(_text.text);

  void _submit(String _) {
    if (_text.text.isEmpty) {
      if (!widget.interactionEnabled ||
          !_available ||
          !_focus.hasFocus ||
          _closing) {
        return;
      }
      if (widget.onCharge != null) {
        _text.clear();
        widget.onCharge!();
      }
      return;
    }
    if (widget.shouldSubmit?.call(_text.text) == false) return;
    // onSubmitted es la única frontera. Copiar antes de limpiar evita que un
    // Enter repetido vuelva a enviar el texto entregado por un callback antiguo.
    final input = _text.text;
    _text.clear();
    final session = _session;
    if (session == null ||
        !widget.interactionEnabled ||
        !_available ||
        !_focus.hasFocus ||
        _closing) {
      return;
    }
    final admission = session.submit(input);
    if (admission == PhysicalBarcodeReadAdmission.invalid) {
      setState(() => _notice = 'El código debe tener hasta 32 dígitos.');
    }
  }

  void _changed() {
    final session = _session;
    if (!mounted || session == null) return;
    final result = session.lastResult;
    if (result != null && !identical(result, _shownResult)) {
      _shownResult = result;
      _notice = switch (result.outcome) {
        SaleBarcodeReadOutcome.added =>
          'Agregado: ${result.candidate!.nombreProducto} · '
              '${result.measuredQuantity ?? "1"} '
              '${result.quantity?.displayUnitSymbol ?? "unidad"}',
        SaleBarcodeReadOutcome.notFound =>
          'No se encontró un artículo con este código.',
        SaleBarcodeReadOutcome.selectionCancelled => 'Selección cancelada.',
        SaleBarcodeReadOutcome.quantityCancelled => 'Cantidad cancelada.',
        SaleBarcodeReadOutcome.unitUnavailable =>
          'La unidad de venta no está disponible.',
        SaleBarcodeReadOutcome.interrupted => 'Lectura interrumpida.',
      };
      if (result.barcodeAssigned) _notice = 'Código guardado. $_notice';
    }
    if (session.isPaused && !widget.searchMode) _text.clear();
    setState(() {});
    if (widget.onAdded != null &&
        !session.isProcessing &&
        session.pendingReadCount == 0 &&
        session.error == null &&
        result?.outcome == SaleBarcodeReadOutcome.added) {
      // Navegar fuera del notify y solo después de liberar toda la cola.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            identical(_session, session) &&
            !session.isProcessing &&
            session.pendingReadCount == 0 &&
            !session.isPaused &&
            !_requiresExplicitResume &&
            _available &&
            !_closing &&
            identical(session.lastResult, result)) {
          widget.onAdded?.call();
        }
      });
    }
  }

  Future<T?> _showReaderDialog<T>(WidgetBuilder builder) =>
      _showReaderInteraction(
        () => showDialog<T>(context: context, builder: builder),
      );

  /// Mantiene la pausa propia durante toda la selección/confirmación, incluso
  /// cuando usa rutas completas. Una ruta externa sigue requiriendo reanudar.
  Future<T?> _showReaderInteraction<T>(Future<T?> Function() show) async {
    final session = _session;
    final generation = _interruptionGeneration;
    if (!mounted || session == null || session.isFinished) return null;
    _ownDialogDepth++;
    final closed = Completer<void>();
    _readerDialogClosed = closed;
    _text.clear();
    try {
      return await show();
    } finally {
      _ownDialogDepth--;
      _readerDialogClosed = null;
      closed.complete();
      if (mounted && identical(_session, session) && !session.isFinished) {
        // El controlador suspende admisión durante el diálogo. La pérdida de
        // foco de ese diálogo no debe convertirse en una pausa externa.
        if (_appActive &&
            _windowFocused &&
            !_closing &&
            session.error == null &&
            generation == _interruptionGeneration) {
          _requestFocus(session);
        }
      }
    }
  }

  /// Se espera `done` antes de permitir cualquier cambio de borrador/contexto.
  Future<void> finish() {
    // Cancelar también una preparación diferida: la navegación puede empezar
    // antes del primer frame o mientras Caja está cubierta/inactiva.
    _preparationRequested = false;
    if (_session == null) return Future<void>.value();
    return _finishOperation ??= _finishSession();
  }

  Future<void> _finishSession() async {
    final session = _session;
    if (session == null) return;
    setState(() => _closing = true);
    if (!widget.searchMode) _text.clear();
    _manualKeyboard = false;
    _focus.unfocus();
    final done = session.finish();
    // Un selector ya visible se resuelve primero. Cubrirlo con el diálogo de
    // drenaje impediría cancelar/confirmar la lectura que finish está esperando.
    await _readerDialogClosed?.future;
    if (!session.isFinished && mounted) {
      _ownDialogDepth++;
      final navigator = Navigator.of(context);
      final route = DialogRoute<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => PhysicalBarcodeFinishDialog(
          controller: session,
          onResume: () {
            if (_appActive && _windowFocused) session.resume();
          },
        ),
      );
      final dialogClosed = navigator.push(route);
      await done;
      if (navigator.mounted && route.isActive) navigator.removeRoute(route);
      await dialogClosed;
      _ownDialogDepth--;
    } else {
      await done;
    }
    if (mounted && session.error != null) {
      // Si falló la última intención, finish ya terminó sin cola. Mantener el
      // error visible antes de abrir la siguiente operación, incluso si el
      // comando pudo guardar y falló al entregar su respuesta.
      _ownDialogDepth++;
      try {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Error de lectura'),
            content: Text(
              session.error is SaleBarcodeAssignedException
                  ? SaleBarcodeAssignedException.message
                  : 'No se pudo confirmar el agregado. Revisa la venta; '
                        'la lectura fallida no se reintentará. '
                        'Los artículos guardados se conservan.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Continuar'),
              ),
            ],
          ),
        );
      } finally {
        _ownDialogDepth--;
      }
    }
    if (mounted && identical(_session, session)) {
      setState(() {
        _session = null;
        _closing = false;
      });
    }
    _finishOperation = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.removeListener(_focusChanged);
    _session?.removeListener(_changed);
    // Un desmontaje forzado invalida consultas; las salidas normales esperan
    // finish desde Caja/Home antes de desmontar este widget.
    _session?.dispose();
    _text.removeListener(_queryChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final ready =
        session != null &&
        session.isAccepting &&
        _focus.hasFocus &&
        _available &&
        !_closing;
    final status = _closing
        ? 'Finalizando lecturas…'
        : session?.isPaused == true || !ready
        ? 'Lector en pausa'
        : session.isSaving
        ? 'Guardando…'
        : 'Listo para escanear';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.searchMode && widget.onOpenSearch == null)
            const Text('Lector físico'),
          if (session != null) ...[
            TextField(
              key: const Key('physical_barcode_input'),
              controller: _text,
              focusNode: _focus,
              readOnly: _closing || !widget.interactionEnabled,
              // Flutter mantiene la conexión editable para HID. En Android,
              // TextInputType.none suprime únicamente el teclado en pantalla.
              keyboardType:
                  defaultTargetPlatform == TargetPlatform.android &&
                      !_manualKeyboard
                  ? TextInputType.none
                  : TextInputType.text,
              textInputAction: TextInputAction.done,
              onEditingComplete: () {},
              onSubmitted: _submit,
              onTap: widget.onOpenSearch == null
                  ? _resume
                  : () {
                      final query = _text.text;
                      widget.onOpenSearch!(query);
                    },
              decoration: InputDecoration(
                labelText: widget.searchMode || widget.onOpenSearch != null
                    ? null
                    : 'Escanea un código y envía Enter',
                hintText: widget.searchMode || widget.onOpenSearch != null
                    ? 'Quiero vender…'
                    : null,
                prefixIcon: widget.onBack == null
                    ? const Icon(Icons.search)
                    : BackButton(onPressed: widget.onBack),
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onScanBarcode != null)
                      IconButton(
                        onPressed: widget.interactionEnabled
                            ? widget.onScanBarcode
                            : null,
                        tooltip: 'Escanear código de barras',
                        icon: const Icon(Icons.barcode_reader),
                      ),
                    if (defaultTargetPlatform == TargetPlatform.android)
                      IconButton(
                        key: const Key('physical_barcode_keyboard'),
                        tooltip: _manualKeyboard
                            ? 'Usar lector físico'
                            : 'Escribir código',
                        onPressed:
                            _closing ||
                                !widget.interactionEnabled ||
                                !_available
                            ? null
                            : _toggleManualKeyboard,
                        icon: Icon(
                          _manualKeyboard
                              ? Icons.barcode_reader
                              : Icons.keyboard,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Semantics(
              liveRegion: true,
              child: Text(
                '$status · ${session.pendingReadCount} lecturas pendientes',
                key: const Key('physical_barcode_status'),
              ),
            ),
            if (session.error != null)
              Text(
                session.error is SaleBarcodeAssignedException
                    ? '${SaleBarcodeAssignedException.message} '
                          'Reanuda las otras lecturas.'
                    : 'No se pudo agregar el artículo. ${switch (session.error) {
                            FormatException error => error.message,
                            StateError error => error.message,
                            _ => '',
                          }} Reanuda las otras lecturas; '
                          'la intención fallida no se reintentará.',
              )
            else if (_notice != null)
              Semantics(liveRegion: true, child: Text(_notice!)),
            if (!ready && !_closing && _ownDialogDepth == 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _available && widget.interactionEnabled
                      ? _resume
                      : null,
                  child: const Text('Reanudar lector'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
