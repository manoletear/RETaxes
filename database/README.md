# Database — Instrucciones de Deploy

## Orden de ejecución obligatorio

```
001_ref_catalogos.sql
  └─▶ 002_ref_parametros_fiscales.sql
        └─▶ 003_ref_vistas_funciones.sql
              └─▶ 004_catastro_portal.sql
                    └─▶ seeds/panguipulli_2025_2.sql  (opcional)
```

## Contenido de cada migración

### 001 — Catálogos de referencia
- Schema `ref`
- `ref.normativa` — Ley 17.235, DS 437, RE 131
- `ref.series_predio` — Agrícola / No Agrícola
- `ref.destinos` — 20 códigos (A-Z)
- `ref.materiales_construccion` — todos los códigos SII
- `ref.calidades_construccion` — 1 (Superior) a 5 (Inferior)
- `ref.clases_construccion`
- `ref.condiciones_especiales` — AL, CA, CI, MS, PZ, SB, TM
- `ref.tipos_suelo_agricola` — 1R, 2R, 3R, 1-8
- `ref.comunas` — 345 comunas con código SII oficial

### 002 — Parámetros fiscales
- `ref.tasas_impuesto` — 0.893%, 1.042%, 1.088%, 1.000%
- `ref.sobretasas` — fiscal 0.025%, SNE 100%, Art. 7°bis
- `ref.montos_exencion` — habitacional, agrícola (con historial)
- `ref.tramos_tasa_habitacional` — monto cambio de tasa $207.288.476
- `ref.depreciacion_construccion` — tablas por año
- `ref.bam_parametros` — Beneficio Adulto Mayor
- `ref.dfl2_parametros` — DFL-2
- `ref.reavaluo_historico` — fechas y tipos de reavalúo
- `ref.reajuste_ipc_semestral` — reajustes históricos
- `ref.factores_homologacion`
- `ref.errores_tipicos` — 11 errores auditables (ERR-C01 a ERR-M01)
- `ref.formulas_calculo` — 12 fórmulas documentadas (F01-F12)
- `ref.parametros_motor` — 16 parámetros de configuración

### 003 — Vistas y funciones
- `ref.v_parametros_vigentes`
- `ref.v_tasas_vigentes`
- `ref.v_exenciones_vigentes`
- `ref.v_resumen_fiscal_vigente`
- `ref.f_calcular_contribucion(avaluo, tipo)` → contribución anual
- `ref.f_depreciacion(anio)` → factor depreciación
- `ref.f_avaluo_construccion(...)` → avalúo construcción
- RLS + políticas SELECT para anon/authenticated
- GRANTs service_role

### 004 — Catastro + Portal Usuario
**Schema `catastro`:**
- `catastro.predios` — tabla maestra ROLs (PK: rol = `CCCC-MMM-P`)
- `catastro.construcciones` — N líneas por ROL
- `catastro.suelos_agricolas` — suelos agrícolas
- `catastro.avaluos_historial` — serie histórica de avalúos
- `catastro.contribuciones_historial` — serie histórica de cobros
- `catastro.importaciones` — control de ingestión masiva

**Schema `public` (portal):**
- `public.usuarios`
- `public.propiedades_usuario`
- `public.documentos_usuario`
- `public.auditorias_usuario`
- `public.casos` (numerados `SNRI-YYYY-NNNN`)

**RPCs:**
- `rpc_validar_rol(rol)`
- `rpc_recalcular_predio_y_caso(rol, caso_id)`
- `rpc_crear_caso_desde_usuario(rol, usuario_id)`
- `rpc_heatmap_usuario(usuario_id)`
- `rpc_estadisticas_comuna(cod_comuna)`

**Utilidades:**
- `catastro.fn_parsear_rol(text)` → `{comuna, manzana, predio}`
- Vistas: `v_rol_resumen`, `v_estadisticas_comuna`, `v_casos_crm`
- Seed de prueba: ROL `15108-624-6` (Algeciras 712, Las Condes)

## Verificación post-install

```sql
SELECT COUNT(*) FROM ref.comunas;                    -- 345
SELECT COUNT(*) FROM ref.errores_tipicos;            -- 11
SELECT COUNT(*) FROM ref.formulas_calculo;           -- 12
SELECT * FROM ref.v_resumen_fiscal_vigente;          -- parámetros 2025
SELECT * FROM catastro.fn_parsear_rol('15108-624-6');
SELECT * FROM ref.f_calcular_contribucion(200000000, 'habitacional');
```

## Seeds disponibles

| Archivo | Comuna | ROLs N | ROLs A | Líneas NL | Líneas AL |
|---------|--------|--------|--------|-----------|-----------|
| `panguipulli_2025_2.sql` | Panguipulli (10108) | 13.679 | 7.078 | 13.158 | 10.301 |
