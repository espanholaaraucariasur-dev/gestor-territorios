import 'package:araucaria_sur/core/services/offline_sync_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('avisa que los cambios se guardan localmente sin conexión',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: OfflineStatusBanner(offline: true, syncing: false),
      ),
    ));

    expect(find.textContaining('Sin conexión'), findsOneWidget);
    expect(
        find.textContaining('se sincronizarán al reconectar'), findsOneWidget);
  });

  testWidgets('muestra el estado mientras Firestore sincroniza',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: OfflineStatusBanner(offline: false, syncing: true),
      ),
    ));

    expect(find.textContaining('Sincronizando cambios pendientes'),
        findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('no ocupa espacio si hay conexión y no hay escrituras pendientes',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: OfflineStatusBanner(offline: false, syncing: false),
      ),
    ));

    expect(find.byType(OfflineStatusBanner), findsOneWidget);
    expect(find.textContaining('Sin conexión'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
