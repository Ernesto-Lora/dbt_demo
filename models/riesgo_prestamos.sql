{{
  config(
    materialized='table',
    schema='analytics',
    tags=['riesgo', 'prestamos']
  )
}}

WITH ingresos_usuarios AS (
  SELECT
    c.usuario_id,
    AVG(CASE 
          WHEN t.tipo_transaccion = 'credito' THEN t.monto 
          ELSE 0 
        END) AS ingreso_promedio_mensual,
    COUNT(DISTINCT CASE 
                     WHEN t.tipo_transaccion = 'credito' THEN t.transaccion_id 
                     ELSE NULL 
                   END) AS frecuencia_ingresos
  FROM {{ source('aviva_challenge', 'transacciones') }} t
  JOIN {{ source('aviva_challenge', 'cuentas') }} c ON t.cuenta_id = c.cuenta_id
  WHERE TIMESTAMP(t.fecha_transaccion) >= TIMESTAMP(DATE_SUB(CURRENT_DATE(), INTERVAL 6 MONTH))
  GROUP BY c.usuario_id
),

deudas_usuarios AS (
  SELECT
    p.usuario_id,
    SUM(p.pago_mensual) AS total_deuda_mensual,
    SUM(p.saldo_pendiente) AS saldo_pendiente_total,
    MAX(p.tasa_interes) AS tasa_interes_maxima
  FROM {{ source('aviva_challenge', 'prestamos') }} p
  WHERE p.estado = 'activo'
  GROUP BY p.usuario_id
),

comportamiento_pago AS (
  SELECT
    p.usuario_id,
    MAX(DATE_DIFF(CURRENT_DATE(), DATE(p.fecha_inicio), DAY)) AS antiguedad_prestamo_dias,
    COUNT(DISTINCT p.prestamo_id) AS num_prestamos_activos
  FROM {{ source('aviva_challenge', 'prestamos') }} p
  WHERE p.estado = 'activo'
  GROUP BY p.usuario_id
)

SELECT
  p.prestamo_id,
  p.usuario_id,
  p.monto_principal,
  p.tasa_interes,
  p.pago_mensual,
  p.saldo_pendiente,
  p.plazo_meses,
  i.ingreso_promedio_mensual,
  d.total_deuda_mensual,
  c.antiguedad_prestamo_dias,
  c.num_prestamos_activos,
  
  -- Ratio deuda/ingresos
  CASE
    WHEN i.ingreso_promedio_mensual > 0 
    THEN ROUND((d.total_deuda_mensual / i.ingreso_promedio_mensual), 2)
    ELSE NULL
  END AS ratio_deuda_ingresos,
  
  -- Perfil de riesgo
  CASE
    WHEN i.ingreso_promedio_mensual = 0 THEN 'Riesgo Extremo (sin ingresos)'
    WHEN (d.total_deuda_mensual / i.ingreso_promedio_mensual) > 0.5 THEN 'Riesgo Alto'
    WHEN (d.total_deuda_mensual / i.ingreso_promedio_mensual) > 0.3 THEN 'Riesgo Medio'
    ELSE 'Riesgo Bajo'
  END AS perfil_riesgo,
  
  -- Capacidad de pago
  CASE
    WHEN i.ingreso_promedio_mensual = 0 THEN 'Sin capacidad'
    WHEN (d.total_deuda_mensual / i.ingreso_promedio_mensual) > 0.6 THEN 'Capacidad limitada'
    WHEN (d.total_deuda_mensual / i.ingreso_promedio_mensual) > 0.4 THEN 'Capacidad moderada'
    ELSE 'Buena capacidad'
  END AS capacidad_pago,
  
  CURRENT_TIMESTAMP() AS fecha_actualizacion
FROM {{ source('aviva_challenge', 'prestamos') }} p
LEFT JOIN ingresos_usuarios i ON p.usuario_id = i.usuario_id
LEFT JOIN deudas_usuarios d ON p.usuario_id = d.usuario_id
LEFT JOIN comportamiento_pago c ON p.usuario_id = c.usuario_id
WHERE p.estado = 'activo'