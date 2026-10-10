import 'dart:async';

import 'package:flutter/material.dart';

import '../../../application/printing/printer_device.dart';
import '../../../application/printing/printer_exception.dart';
import '../../../application/printing/printer_gateway.dart';
import 'printer_access.dart';
import 'printer_failure_message.dart';

class BondedPrintersScreen extends StatefulWidget {
  const BondedPrintersScreen({super.key, required this.gateway});

  final PrinterGateway gateway;

  @override
  State<BondedPrintersScreen> createState() => _BondedPrintersScreenState();
}

class _BondedPrintersScreenState extends State<BondedPrintersScreen> {
  List<PrinterDevice> _devices = const [];
  bool _loading = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _devices = const [];
      _message = null;
    });
    try {
      if (!await requestPrinterAccess(
        widget.gateway,
        isActive: () => mounted && (ModalRoute.of(context)?.isCurrent ?? true),
      )) {
        return;
      }
      final devices = await widget.gateway.bondedDevices().timeout(
        const Duration(seconds: 35),
      );
      if (!mounted) return;
      setState(() {
        _devices = devices;
        if (devices.isEmpty) _message = 'No hay dispositivos vinculados.';
      });
    } on PrinterException catch (error) {
      if (mounted) {
        setState(() => _message = printerFailureMessage(error.failure));
      }
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _message = printerFailureMessage(PrinterFailure.timeout),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = printerFailureMessage(PrinterFailure.transportError),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Dispositivos vinculados')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Para vincular una impresora, abre Ajustes del sistema → Bluetooth, '
          'vincula el equipo y vuelve aquí para recargar. Esta app consulta '
          'solo dispositivos ya vinculados.',
        ),
        const SizedBox(height: 12),
        const Text(
          'La lista puede incluir otros equipos. Estar vinculado no garantiza '
          'compatibilidad ESC/POS por Bluetooth Classic/SPP.',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _loading ? null : _reload,
          icon: const Icon(Icons.refresh),
          label: const Text('Recargar'),
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(_message!),
          ),
        for (final device in _devices)
          ListTile(
            key: ValueKey(device.address),
            leading: const Icon(Icons.bluetooth),
            title: Text(
              device.name?.trim().isNotEmpty == true
                  ? device.name!
                  : 'Dispositivo sin nombre',
            ),
            subtitle: Text(device.address),
            onTap: () => Navigator.of(context).pop(device),
          ),
      ],
    ),
  );
}
