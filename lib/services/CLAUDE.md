# Araucaria Sur — Contexto del Proyecto

## Descripción
App Flutter con Firebase para gestión de territorios de predicación.
Congregación Araucaria Sur, Araucária - PR, Brasil.

## Arquitectura
- Flutter Web + Firebase (Firestore)
- Estructura: `lib/features/home/presentation/pages/`

## Roles de Usuario
| Rol | Permisos |
|-----|----------|
| **Admin** | Crear territorios, tarjetas, agregar direcciones al CSV. NO envía, NO programa, NO libera candados |
| **Admin Territorios** | Enviar tarjetas/territorios, programar envíos, abrir/cerrar candados. NO edita ni elimina |
| **Conductor** | Recibe territorios del admin, envía tarjetas a publicadores |
| **Publicador** | Recibe tarjetas, marca direcciones como visitadas |
| **Localizador** | Busca direcciones en el directorio global |

## Estructura de Archivos
```
lib/features/home/presentation/pages/
├── home_page.dart                    ← Página principal, TabController
├── admin/
│   ├── admin_tab.dart               ← TabBar admin (4 tabs: Estructura, Territorios, Comunicación, Usuarios)
│   ├── admin_territorios_tab.dart   ← Contenedor tabs territorios (4 tabs)
│   ├── territorios_tab.dart         ← Tab territorios (admin territorios role)
│   ├── temporales_tab.dart          ← Tab tarjetas temporales
│   ├── devueltas_tab.dart           ← Tab tarjetas devueltas
│   ├── estadisticas_tab.dart        ← Tab estadísticas
│   ├── comunicacion_tab.dart        ← Tab comunicación
│   ├── usuarios_tab.dart            ← Tab gestión usuarios
│   ├── mantenimiento_tab.dart       ← Tab mantenimiento (modo dev oculto, 7 taps)
│   └── restauracion_mensual.dart    ← Servicio restauración automática día 1 del mes
├── conductor/
│   └── conductor_tab.dart
├── publicador/
│   └── publicador_tab.dart
└── localizador/
    └── localizador_tab.dart
```

## Firestore Collections
- `direcciones_globales` — Todas las direcciones. Campos clave: `calle`, `complemento`, `barrio`, `territorio_id`, `tarjeta_id`, `estado_predicacion`, `predicado`, `visitado`
- `territorios` — Territorios. Subcollección: `tarjetas`
- `territorios/{id}/tarjetas` — Tarjetas de cada territorio. Campos: `nombre`, `bloqueado`, `disponible_para_publicadores`, `es_temporal`, `tipo`, `estatus_envio`
- `usuarios` — Usuarios. Campos: `es_admin`, `es_conductor`, `es_publicador`, `es_admin_territorios`, `estado`, `nombre`, `email`
- `sistema` — Metadatos del sistema. Doc: `restauracion_mensual`

## Lógica de Candados
- Por defecto todas las tarjetas están **bloqueadas** (`bloqueado: true`, `disponible_para_publicadores: false`)
- Admin Territorios abre el candado del territorio → libera TODAS las tarjetas del territorio
- Admin Territorios puede abrir/cerrar candado de tarjetas individuales
- Reinicio mensual → cierra todos los candados automáticamente

## Restauración Mensual (día 1 de cada mes)
- SÍ restaura: `visitado`, `predicado`, `estado_predicacion`, asignaciones, candados
- NO restaura: estadísticas, tarjetas temporales (`tipo == 'temporal'`)
- Registra ejecución en `sistema/restauracion_mensual`

## Modo Desarrollador
- Activar: 7 taps rápidos en el título "🔧 Mantenimiento del Sistema"
- Muestra botones ocultos: LIMPIAR TODO, Restaurar tarjeta_id, Limpiar datos dinámicos, Limpiar huérfanas
- Solo visible para admin en la pestaña Mantenimiento

## Tareas Pendientes
1. [ ] admin_tab.dart — eliminar 4 botones sueltos y métodos duplicados, agregar tab Mantenimiento (5to tab)
2. [ ] home_page.dart — TabController length 4 → 5
3. [ ] Implementar lógica real de: _mostrarDialogoCrearTerritorio, _levantarArchivoCSV, _verDirectorioGlobal, _editarNombreTerritorio, _mostrarDialogoCrearTarjeta, _agregarDireccionesATarjeta
4. [ ] Tarjetas temporales — slider progresivo, crear, enviar
5. [ ] Publicador — radio buttons para marcar direcciones
6. [ ] Conductor — enviar tarjeta a publicador
7. [ ] Limpiar base de datos y cargar datos frescos
8. [ ] Deploy a Firebase Hosting

## Notas Importantes
- El ID del documento en `direcciones_globales` sigue el patrón: `Territorio_Tarjeta_Dirección_timestamp`
- Las tarjetas en Firestore usan su nombre como ID (ej: `D02`, `A01`)
- `cantidad_direcciones` en tarjetas NO es confiable — siempre contar desde `direcciones_globales`
- No usar `withOpacity()` — usar `withValues(alpha: x)`
- No usar `RadioListTile` con `groupValue/onChanged` deprecated — usar `RadioGroup`