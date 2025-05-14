-- models/prueba_conexion.sql
SELECT
  current_timestamp() as momento_ejecucion,
  'Conexión exitosa con BigQuery' as mensaje,
  COUNT(*) as total_usuarios,
  MIN(fecha_registro) as fecha_primer_usuario,
  MAX(fecha_registro) as fecha_ultimo_usuario
FROM `aviva-challenge.avivaChallenge.usuarios`  
