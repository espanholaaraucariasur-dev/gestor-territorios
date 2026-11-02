import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:araucaria_sur/core/services/ruta_orden_service.dart';
import 'package:araucaria_sur/features/home/presentation/pages/publicador/navegacion_screen.dart';

/// Pruebas de la ventana flotante del mapa.
///
/// Se enfocan en lo que el usuario pidió: al minimizar, la app de abajo sigue
/// usable (los toques atraviesan la ruta) y el mini-mapa queda visible; al
/// ampliar, vuelve el mapa a pantalla completa sin romperse.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Evita MissingPluginException de geolocator / flutter_tts en el test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/geolocator'),
      (call) async => null,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_tts'),
      (call) async => 1,
    );
  });

  const destinos = [
    DireccionRuta(id: 'a1', nombre: 'Rua Teste 100', lat: -23.5, lng: -51.5),
    DireccionRuta(id: 'a2', nombre: 'Rua Teste 200', lat: -23.51, lng: -51.51),
  ];

  /// Monta la app con un botón de fondo ("Marcar predicado") que registra si
  /// recibe el toque. La navegación se abre con la ruta transparente.
  Future<List<String>> montar(WidgetTester tester) async {
    final tocados = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('marcar'),
              onPressed: () => tocados.add('marcar'),
              child: const Text('Marcar predicado'),
            ),
          ),
        ),
      ),
    ));

    final context = tester.element(find.byKey(const Key('marcar')));
    Navigator.of(context).push(
      RutaNavegacionTransparente<Object?>(
        pageBuilder: (_, __, ___) => const NavegacionScreen(
          titulo: 'Tarjeta de prueba',
          destinos: destinos,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tocados;
  }

  testWidgets('al abrir navegación se ve el mapa a pantalla completa',
      (tester) async {
    await montar(tester);
    expect(find.text('Tarjeta de prueba'), findsWidgets);
    expect(find.byIcon(Icons.picture_in_picture_alt), findsOneWidget);
    expect(find.byIcon(Icons.open_in_full), findsNothing);
  });

  testWidgets('minimizar muestra la ventana flotante con Ampliar y Cerrar',
      (tester) async {
    await montar(tester);

    await tester.tap(find.byIcon(Icons.picture_in_picture_alt));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.open_in_full), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
    // El botón de pantalla completa ya no está.
    expect(find.byIcon(Icons.picture_in_picture_alt), findsNothing);
  });

  testWidgets('estando minimizado, la app de abajo recibe los toques',
      (tester) async {
    final tocados = await montar(tester);

    await tester.tap(find.byIcon(Icons.picture_in_picture_alt));
    await tester.pumpAndSettle();

    // Toca el botón de la app de abajo (centro). Si la ruta absorbiera los
    // toques, este botón nunca se dispararía.
    await tester.tap(find.byKey(const Key('marcar')));
    await tester.pumpAndSettle();

    expect(tocados, contains('marcar'));
  });

  testWidgets('Ampliar restaura el mapa a pantalla completa', (tester) async {
    await montar(tester);

    await tester.tap(find.byIcon(Icons.picture_in_picture_alt));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.open_in_full), findsOneWidget);

    await tester.tap(find.byIcon(Icons.open_in_full));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.picture_in_picture_alt), findsOneWidget);
    expect(find.byIcon(Icons.open_in_full), findsNothing);
  });

  testWidgets('Cerrar sale de la navegación y vuelve a la app',
      (tester) async {
    await montar(tester);

    await tester.tap(find.byIcon(Icons.picture_in_picture_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Marcar predicado'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_full), findsNothing);
  });

  testWidgets('minimizado sobrevive a un diálogo abierto desde abajo',
      (tester) async {
    final tocados = await montar(tester);

    await tester.tap(find.byIcon(Icons.picture_in_picture_alt));
    await tester.pumpAndSettle();

    // Simula el flujo real (p. ej. enviar tarjeta): abrir un diálogo desde la
    // app de abajo y luego cerrarlo. El mini-mapa debe seguir ahí.
    final context = tester.element(find.byKey(const Key('marcar')));
    showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (_) => AlertDialog(
        title: const Text('Enviar tarjeta'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enviar tarjeta'), findsOneWidget);
    expect(find.byIcon(Icons.open_in_full), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    // El mini-mapa sigue visible y usable tras cerrar el diálogo.
    expect(find.byIcon(Icons.open_in_full), findsOneWidget);
    await tester.tap(find.byKey(const Key('marcar')));
    await tester.pumpAndSettle();
    expect(tocados, contains('marcar'));
  });
}
