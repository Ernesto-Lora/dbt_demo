{{
  config(
    materialized='table',
    schema='analytics'
  )
}}

WITH estadisticas_transacciones AS (
  SELECT
    u.usuario_id,
    MAX(t.fecha_transaccion) AS ultima_transaccion,
    COUNT(t.transaccion_id) AS total_transacciones,
    SUM(t.monto) AS gasto_total,
    AVG(t.monto) AS promedio_transaccion
  FROM {{ source('aviva_challenge', 'usuarios') }} u
  JOIN {{ source('aviva_challenge', 'cuentas') }} c ON u.usuario_id = c.usuario_id
  JOIN {{ source('aviva_challenge', 'transacciones') }} t ON c.cuenta_id = t.cuenta_id
  WHERE t.tipo_transaccion = 'debito'
  GROUP BY u.usuario_id
),

rfm AS (
  SELECT
    usuario_id,
    gasto_total,
    DATE_DIFF(
      DATE(CURRENT_TIMESTAMP()), 
      DATE(ultima_transaccion), 
      DAY
    ) AS dias_desde_ultima_compra,
    NTILE(5) OVER (ORDER BY DATE_DIFF(
      DATE(CURRENT_TIMESTAMP()), 
      DATE(ultima_transaccion), 
      DAY
    ) DESC) AS puntuacion_recencia,
    NTILE(5) OVER (ORDER BY total_transacciones) AS puntuacion_frecuencia,
    NTILE(5) OVER (ORDER BY gasto_total) AS puntuacion_monetario,
    promedio_transaccion
  FROM estadisticas_transacciones
)

SELECT
  r.usuario_id,
  r.gasto_total,
  r.dias_desde_ultima_compra,
  (r.puntuacion_recencia + r.puntuacion_frecuencia + r.puntuacion_monetario) AS puntuacion_rfm,
  r.promedio_transaccion,
  CASE
    WHEN (r.puntuacion_recencia + r.puntuacion_frecuencia + r.puntuacion_monetario) >= 12 THEN 'Alto LTV'
    WHEN (r.puntuacion_recencia + r.puntuacion_frecuencia + r.puntuacion_monetario) >= 8 THEN 'Medio LTV'
    ELSE 'Bajo LTV'
  END AS segmento_ltv,
  CURRENT_TIMESTAMP() AS fecha_actualizacion
FROM rfm r