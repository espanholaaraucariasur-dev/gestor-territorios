---
description: Prepara todo el entorno de desarrollo de Araucaria Sur (herramientas, MCP, skills, builds). Ejecutar una sola vez tras clonar.
agent: build
---

Actúa como un ingeniero DevOps experto. Prepara TODO el entorno de desarrollo del proyecto Flutter/Firebase **gestor-territorios** (app "Araucaria Sur"). Hazlo paso a paso verificando cada uno.

Contexto: app Flutter para una congregación. Stack: Flutter, Firebase (Auth + Firestore + Hosting). Reglas del código en AGENTS.md.

PASO 1: Detecta el sistema operativo y verifica si están instalados git, node, npm, flutter, dart, docker. Reporta qué hay y qué falta.

PASO 2: Instala lo que falte:
- Git (si falta).
- Node.js LTS (si falta).
- Flutter SDK (si falta): seguir la doc oficial para Windows (`C:\src\flutter` + agregar `C:\src\flutter\bin` al PATH) y luego `flutter doctor` corrigiendo lo posible.
- Docker: opcional, solo avisar si no está.

PASO 3: Verifica que opencode esté instalado (si no, instalarlo: Windows `irm https://opencode.ai/install | iex`).

PASO 4: Verifica que el proyecto esté clonado en la carpeta actual. Si no, clona: `git clone https://github.com/espanholaaraucariasur-dev/gestor-territorios.git .`

PASO 5: Crea o edita `~/.config/opencode/opencode.json` (Windows: `C:\Users\<usuario>\.config\opencode\opencode.json`) haciendo MERGE (conserva lo existente) y agregando SOLO si falta este bloque de MCP:
```json
{
  "mcp": {
    "playwright": { "type": "local", "command": ["npx", "-y", "@playwright/mcp@latest"], "enabled": true },
    "supabase": { "type": "local", "command": ["npx", "-y", "@supabase/mcp-server-supabase@latest"], "environment": { "SUPABASE_ACCESS_TOKEN": "{env:SUPABASE_ACCESS_TOKEN}" }, "enabled": true },
    "context7": { "type": "local", "command": ["npx", "-y", "@upstash/context7-mcp"], "enabled": true }
  }
}
```

PASO 6: Instala las skills globales en `~/.agents/skills/` con el CLI de skills:
1. `npx -y skills@latest add hardikpandya/stop-slop`
2. `npx -y skills@latest add nidhinjs/prompt-master`
3. `npx -y skills@latest add remotion-dev/skills`
4. `npx -y skills@latest add nextlevelbuilder/ui-ux-pro-max-skill`
Después de cada una, si quedó en una carpeta local `.agents/skills` del proyecto, muévela a `~/.agents/skills/`. Verifica que cada `~/.agents/skills/<nombre>/SKILL.md` exista.

PASO 7: Ejecuta `flutter pub get` en la carpeta del proyecto.

PASO 8: Verificación final:
- `flutter analyze` (debe dar 0 errores; warnings/info preexistentes del proyecto OK).
- `flutter build web --release` (debe compilar).
- `flutter build apk --release` (si tarda demasiado, avisa y continúa).

Reporte final con este formato:
```
✅ ENTORNO LISTO
OS: ...
Git: ... | Node: ... | Flutter: ... | Docker: ...
Proyecto clonado en: ...
opencode.json: configurado | Skills: N instaladas
flutter analyze: OK | flutter build web: OK | flutter build apk: ...
Próximo paso para el usuario: ...
```

IMPORTANTE: no hagas push ni commits. No modifiques código de la app. Solo prepara el entorno y verifica. Reporta en español.