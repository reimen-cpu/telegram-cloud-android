Plan: Reintentos Exponenciales y Resumen de Uploads/Descargas Interrumpidos
Objetivo
Implementar sistema robusto de uploads Y descargas con:

Reintentos exponenciales para errores temporales (red, rate limits, 5xx)
Persistencia del progreso de chunks para reanudar uploads/descargas interrumpidos
Detección automática de uploads/descargas incompletos al reiniciar la app
Cambios en Base de Datos
1. Extender UploadTaskEntity (android/app/src/main/java/com/telegram/cloud/data/local/CloudEntities.kt)
Agregar campo fileId: String? para UUID del upload chunked
Agregar campo completedChunksJson: String? para guardar JSON con chunks completados
Agregar campo tokenOffset: Int para recordar el offset de tokens usado (default 0)
Crear migración de base de datos (versión 4 → 5)
2. Extender DownloadTaskEntity (android/app/src/main/java/com/telegram/cloud/data/local/CloudEntities.kt)
Agregar campo completedChunksJson: String? para guardar JSON con índices de chunks descargados
Agregar campo chunkFileIds: String? para guardar lista de file IDs de chunks (comma-separated)
Agregar campo tempChunkDir: String? para guardar ruta del directorio temporal de chunks
Agregar campo totalChunks: Int para número total de chunks (default 0)
Incluir en migración de base de datos (versión 4 → 5)
Cambios en ChunkedUploadManager
3. Modificar uploadChunked() (android/app/src/main/java/com/telegram/cloud/data/remote/ChunkedUploadManager.kt)
Agregar parámetro opcional skipChunks: Set<Int> = emptySet() para omitir chunks ya completados
Agregar callback opcional onChunkCompleted: ((ChunkInfo) -> Unit)? = null para guardar progreso
Filtrar jobs para omitir chunks en skipChunks antes de crear async jobs
Guardar progreso después de cada chunk exitoso usando el callback
4. Implementar reintentos exponenciales en uploadSingleChunk() (android/app/src/main/java/com/telegram/cloud/data/remote/ChunkedUploadManager.kt)
Envolver llamada a botClient.sendChunk() con lógica de reintentos
5 reintentos máximo con backoff exponencial: 1s, 2s, 4s, 8s, 16s
Solo reintentar errores recuperables: IOException, SocketTimeoutException, 429, 500, 502, 503, 504
No reintentar errores críticos: 400, 401, 403, 404, IllegalArgumentException
Log detallado de cada intento con backoff time
5. Agregar método resumeChunkedUpload() (android/app/src/main/java/com/telegram/cloud/data/remote/ChunkedUploadManager.kt)
Aceptar fileId: String, completedChunks: List<ChunkInfo>, tokenOffset: Int, y demás parámetros normales
Reconstruir estado del upload desde chunks completados
Extraer set de índices de chunks completados para skipChunks
Llamar a uploadChunked() con skipChunks y onChunkCompleted configurados
Cambios en ChunkedDownloadManager
6. Mejorar reintentos exponenciales en downloadSingleChunk() (android/app/src/main/java/com/telegram/cloud/data/remote/ChunkedDownloadManager.kt)
Ya tiene reintentos básicos (línea 206-239) pero solo 3 intentos con backoff simple
Mejorar a 5 reintentos con backoff exponencial: 1s, 2s, 4s, 8s, 16s
Mejorar detección de errores recuperables vs críticos
Mejorar logging de reintentos con información detallada
7. Modificar downloadChunked() (android/app/src/main/java/com/telegram/cloud/data/remote/ChunkedDownloadManager.kt)
Agregar parámetro opcional skipChunks: Set<Int> = emptySet() para omitir chunks ya descargados
Agregar parámetro opcional existingChunkDir: File? = null para usar directorio temporal existente
Agregar callback opcional onChunkDownloaded: ((Int, File) -> Unit)? = null para guardar progreso
No eliminar directorio temporal inmediatamente, guardar referencia para resumen
Guardar chunks descargados a archivos individuales en tempDir: chunk_${index}.tmp
Verificar si archivo chunk_${index}.tmp ya existe antes de descargar (reanudación)
Cargar chunks existentes desde archivos en tempDir al inicio
Filtrar jobs para omitir chunks en skipChunks y chunks ya descargados
8. Agregar método resumeChunkedDownload() (android/app/src/main/java/com/telegram/cloud/data/remote/ChunkedDownloadManager.kt)
Aceptar chunkFileIds: List<String>, completedChunkIndices: Set<Int>, tempChunkDir: File, y demás parámetros
Verificar chunks existentes en tempDir y añadirlos a completedChunkIndices
Llamar a downloadChunked() con skipChunks, existingChunkDir, y onChunkDownloaded configurados
Cambios en TelegramRepository
9. Modificar uploadChunked() (android/app/src/main/java/com/telegram/cloud/data/repository/TelegramRepository.kt)
Antes de iniciar upload, verificar si hay progreso guardado en UploadTaskEntity usando taskId
Si existe fileId y completedChunksJson no vacío, parsear JSON y reanudar usando resumeChunkedUpload()
Si no hay progreso, generar nuevo fileId (UUID) y guardar en UploadTaskEntity al iniciar
Guardar progreso después de cada chunk usando callback onChunkCompleted
Serializar List<ChunkInfo> a JSON usando Gson o kotlinx.serialization
Guardar JSON actualizado en completedChunksJson después de cada chunk
Actualizar tokenOffset en UploadTaskEntity si se especifica
10. Agregar método getIncompleteUploads() (android/app/src/main/java/com/telegram/cloud/data/repository/TelegramRepository.kt)
Consultar UploadTaskDao para tareas con status RUNNING o FAILED que tengan fileId no nulo
Filtrar tareas que tengan completedChunksJson (indica que es chunked)
Retornar lista de UploadTaskEntity que pueden reanudarse
Usar para detectar uploads interrumpidos al iniciar la app
11. Agregar método resumeUpload() (android/app/src/main/java/com/telegram/cloud/data/repository/TelegramRepository.kt)
Aceptar taskId: Long
Cargar UploadTaskEntity por taskId
Parsear completedChunksJson a List<ChunkInfo> usando deserialización JSON
Verificar que fileId no sea nulo
Cargar UploadRequest desde la entidad (reconstruir desde uri, displayName, sizeBytes)
Llamar a chunkedUploadManager.resumeChunkedUpload() con chunks completados
Actualizar status a RUNNING en UploadTaskEntity
12. Modificar download() (android/app/src/main/java/com/telegram/cloud/data/repository/TelegramRepository.kt)
Detectar si es archivo chunked usando ChunkedDownloadManager.isChunkedFile(caption)
Para archivos chunked:
Extraer chunkFileIds desde fileUniqueId (comma-separated) o desde caption
Si taskId está disponible, verificar progreso guardado en DownloadTaskEntity
Si existe completedChunksJson y tempChunkDir, parsear y reanudar
Guardar chunkFileIds, tempChunkDir, totalChunks en DownloadTaskEntity al iniciar
Guardar progreso después de cada chunk descargado
Serializar índices de chunks completados a JSON y guardar en completedChunksJson
Para archivos no chunked, comportamiento sin cambios
13. Agregar método getIncompleteDownloads() (android/app/src/main/java/com/telegram/cloud/data/repository/TelegramRepository.kt)
Consultar DownloadTaskDao para tareas con status RUNNING o FAILED que tengan totalChunks > 0
Filtrar tareas que tengan chunkFileIds no nulo (indica que es chunked)
Verificar que tempChunkDir existe y es válido
Retornar lista de DownloadTaskEntity que pueden reanudarse
Usar para detectar descargas interrumpidas al iniciar la app
14. Agregar método resumeDownload() (android/app/src/main/java/com/telegram/cloud/data/repository/TelegramRepository.kt)
Aceptar taskId: Long
Cargar DownloadTaskEntity por taskId
Parsear completedChunksJson a Set<Int> (índices de chunks completados)
Verificar que tempChunkDir existe como File
Parsear chunkFileIds (comma-separated) a List<String>
Reconstruir CloudFile desde la entidad o desde la base de datos usando fileId
Llamar a chunkedDownloadManager.resumeChunkedDownload() con chunks completados
Actualizar status a RUNNING en DownloadTaskEntity
Cambios en Workers
15. Modificar UploadWorker.doWork() (android/app/src/main/java/com/telegram/cloud/gallery/UploadWorker.kt)
Obtener taskId desde inputData
Antes de llamar a repository.upload(), verificar si hay progreso guardado usando taskId
Si existe progreso y es chunked, llamar a repository.resumeUpload(taskId) en lugar de upload()
Manejar errores de resumen y fallback a upload normal si falla o no hay progreso
16. Modificar DownloadWorker.doWork() (android/app/src/main/java/com/telegram/cloud/gallery/DownloadWorker.kt)
Obtener taskId desde inputData (agregar si no existe)
Antes de llamar a repository.download(), verificar si hay progreso guardado usando taskId
Si existe progreso y es chunked, llamar a repository.resumeDownload(taskId) en lugar de download()
Manejar errores de resumen y fallback a descarga normal si falla o no hay progreso
Mejoras en TelegramBotClient
17. Mejorar manejo de reintentos en sendChunk() (android/app/src/main/java/com/telegram/cloud/data/remote/TelegramBotClient.kt)
Ya tiene lógica básica para rate limiting (429) en líneas 374-391
Extender para manejar otros códigos HTTP recuperables (500, 502, 503, 504)
Agregar backoff exponencial más robusto para errores 5xx
Mejorar logging de reintentos con información detallada
Inicialización y Limpieza
18. Agregar detección de uploads/descargas incompletos al iniciar (android/app/src/main/java/com/telegram/cloud/ui/MainViewModel.kt)
En init del ViewModel
Llamar a repository.getIncompleteUploads() y repository.getIncompleteDownloads()
Opcionalmente reanudar automáticamente agregando tareas a las colas
O mostrar notificación al usuario para que decida reanudar manualmente
19. Agregar limpieza de estados antiguos
Crear método en TelegramRepository para limpiar tareas antiguas
Limpiar UploadTaskEntity con status COMPLETED o FAILED después de 7 días
Limpiar DownloadTaskEntity con status COMPLETED o FAILED después de 7 días
Limpiar directorios temporales de chunks huérfanos (>7 días sin uso)
Ejecutar al iniciar la app y periódicamente (opcional)
Consideraciones Técnicas
Serialización JSON: Usar Gson (ya incluido en el proyecto) para serializar/deserializar List<ChunkInfo> y Set<Int>
Thread Safety: Asegurar que guardado de progreso sea thread-safe (ya usa synchronized para chunkInfos y chunkDataMap)
Migración de BD: Crear CloudDatabase.MIGRATION_4_5 que agregue nuevos campos con valores por defecto (null, 0, etc.)
Backward Compatibility: Uploads/descargas existentes sin campos nuevos deben funcionar normalmente (upload/descarga desde cero)
Gestión de archivos temporales: No eliminar tempChunkDir hasta que el upload/descarga esté completamente completo
Archivos a Modificar
android/app/src/main/java/com/telegram/cloud/data/local/CloudEntities.kt - Extender entidades y crear migración
android/app/src/main/java/com/telegram/cloud/data/remote/ChunkedUploadManager.kt - Reintentos y resumen
android/app/src/main/java/com/telegram/cloud/data/remote/ChunkedDownloadManager.kt - Reintentos y resumen
android/app/src/main/java/com/telegram/cloud/data/repository/TelegramRepository.kt - Lógica de resumen
android/app/src/main/java/com/telegram/cloud/gallery/UploadWorker.kt - Detección de resumen
android/app/src/main/java/com/telegram/cloud/gallery/DownloadWorker.kt - Detección de resumen
android/app/src/main/java/com/telegram/cloud/data/remote/TelegramBotClient.kt - Mejorar reintentos (opcional)
android/app/src/main/java/com/telegram/cloud/ui/MainViewModel.kt - Detección al iniciar
Testing
Probar upload normal (sin interrupciones)
Probar descarga normal (sin interrupciones)
Probar interrupción a mitad de upload (cerrar app)
Probar interrupción a mitad de descarga (cerrar app)
Probar resumen después de interrupción (upload)
Probar resumen después de interrupción (descarga)
Probar reintentos con errores de red simulados
Probar rate limiting (429) con múltiples reintentos
Probar que chunks ya completados no se vuelvan a subir/descargar
Probar limpieza de estados antiguos
