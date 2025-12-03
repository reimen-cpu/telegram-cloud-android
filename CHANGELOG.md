# Changelog

Todos los cambios notables en este proyecto serán documentados en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/),
y este proyecto adhiere a [Semantic Versioning](https://semver.org/lang/es/).

## [1.0.0] - 2025-01-XX

### Añadido
- Interfaz principal con Jetpack Compose y Material Design 3
- Subida y descarga de archivos usando Telegram Bot API
- Sincronización de galería de medios (fotos y videos)
- Sistema de backups cifrados con contraseña
- Generación y descarga de archivos `.link` para compartir múltiples archivos
- Búsqueda y filtrado de archivos
- Cola de tareas con WorkManager para operaciones en segundo plano
- Base de datos cifrada con SQLCipher
- Soporte para múltiples ABIs (arm64-v8a, armeabi-v7a)
- Integración con código nativo C++ compartido (telegram-cloud-cpp)
- Reproducción de videos con Media3/ExoPlayer
- Gestión de permisos de Android 13+ (Media permissions)

### Seguridad
- Almacenamiento seguro de credenciales con DataStore
- Cifrado de base de datos local
- Backups protegidos con contraseña

### Requisitos
- Android 9.0 (API 28) o superior
- Bot de Telegram configurado
- Canal de Telegram (opcional)

---

[1.0.0]: https://github.com/usuario/repositorio/releases/tag/v1.0.0

