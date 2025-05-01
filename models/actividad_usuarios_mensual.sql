-- modelos/actividad_usuarios_mensual.sql
{{
  config(
    materialized='table'
  )
}}

WITH usuarios_activos_mensuales AS (
  SELECT
    DATE_TRUNC(t.fecha_transaccion, MONTH) AS mes,
    COUNT(DISTINCT u.usuario_id) AS cantidad_usuarios_activos,
    COUNT(t.transaccion_id) AS cantidad_transacciones,
    SUM(ABS(t.monto)) AS volumen_transacciones
  FROM {{ source('aviva_challenge', 'usuarios') }} u
  JOIN {{ source('aviva_challenge', 'cuentas') }} c ON u.usuario_id = c.usuario_id
  JOIN {{ source('aviva_challenge', 'transacciones') }} t ON c.cuenta_id = t.cuenta_id
  WHERE t.estado = 'completado'  -- Only count completed transactions
  GROUP BY 1
),

calculo_crecimiento AS (
  SELECT
    mes,
    cantidad_usuarios_activos,
    cantidad_transacciones,
    volumen_transacciones,
    LAG(cantidad_usuarios_activos, 1) OVER (ORDER BY mes) AS usuarios_mes_anterior,
    LAG(cantidad_transacciones, 1) OVER (ORDER BY mes) AS transacciones_mes_anterior,
    LAG(volumen_transacciones, 1) OVER (ORDER BY mes) AS volumen_mes_anterior
  FROM usuarios_activos_mensuales
)

SELECT
  mes,
  cantidad_usuarios_activos,
  cantidad_transacciones,
  volumen_transacciones,
  ROUND((cantidad_usuarios_activos - usuarios_mes_anterior) * 100.0 / NULLIF(usuarios_mes_anterior, 0), 2) AS crecimiento_usuarios_pct,
  ROUND((cantidad_transacciones - transacciones_mes_anterior) * 100.0 / NULLIF(transacciones_mes_anterior, 0), 2) AS crecimiento_transacciones_pct,
  ROUND((volumen_transacciones - volumen_mes_anterior) * 100.0 / NULLIF(volumen_mes_anterior, 0), 2) AS crecimiento_volumen_pct,
  ROUND(volumen_transacciones/NULLIF(cantidad_usuarios_activos, 0), 2) AS volumen_promedio_por_usuario,
  ROUND(cantidad_transacciones/NULLIF(cantidad_usuarios_activos, 0), 2) AS transacciones_promedio_por_usuario
FROM calculo_crecimiento
ORDER BY mes