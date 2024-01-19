/*
# Copyright (c) 2021-2025 University of Missouri                   
# Author: Xing Song, xsm7f@umsystem.edu                            
# File: wt-cms-mu-clinic.sql                                            
*/
-- check availability of dependency tables
select * from WT_MU_EHR_ELIG_TBL2 limit 5;
select * from GROUSE_DB.CMS_PCORNET_CDM.LDS_DIAGNOSIS limit 5;
select * from GROUSE_DB.PCORNET_CDM_MU.LDS_DIAGNOSIS limit 5;
select * from GROUSE_DB.GROUPER_VALUESETS.ICD9DX_CCS limit 5;
select * from GROUSE_DB.CMS_PCORNET_CDM.LDS_PROCEDURES limit 5;
select * from GROUSE_DB.PCORNET_CDM_MU.LDS_PROCEDURES limit 5;
select * from GROUSE_DB.CMS_PCORNET_CDM.LDS_DISPENSING limit 5;
select * from GROUSE_DB.PCORNET_CDM_MU.LDS_VITAL limit 5;
select * from Z_REF_CCI;

-- get clinical features each pat-enc
create or replace table WT_MU_DX as 
select a.patid
      ,dx.encounterid
      ,dx.enc_type
      ,dx.dx
      ,dx.dx_type
      ,dx.dx_date
from WT_MU_EHR_ELIG_TBL2 a 
join GROUSE_DB.CMS_PCORNET_CDM.LDS_DIAGNOSIS dx 
on a.patid = dx.patid
union 
select a.patid
      ,dx.encounterid
      ,dx.enc_type
      ,dx.dx
      ,dx.dx_type
      ,dx.dx_date
from WT_MU_EHR_ELIG_TBL2 a 
join GROUSE_DB.PCORNET_CDM_MU.LDS_DIAGNOSIS dx 
on a.patid = dx.patid
;
select count(distinct patid) from WT_MU_DX;
-- 57133
select * from WT_MU_DX
where dx_type = '09'
limit 5;

create or replace table WT_MU_CCI as
select  distinct
        dx.patid,
        dx.dx_date as cci_date,
        cci.code_grp,
        cci.full as code_grp_lbl,
        cci.score as cci_score
from WT_MU_DX dx
join Z_REF_CCI cci 
on dx.dx like cci.code || '%' and 
   dx.dx_type = lpad(cci.code_type,2,'0')
; 
select count(distinct patid) from WT_MU_CCI;
-- 46531

create or replace table WT_MU_DX_CCS as 
with cte_ccs as (
    select distinct dx.*,
           ccs.ccs_slvl1 as ccs_dxgrpcd, 
           ccs.ccs_slvl1label as ccs_dxgrp
    from WT_MU_DX dx 
    join GROUSE_DB.GROUPER_VALUESETS.ICD10CM_CCS ccs 
    on replace(dx.DX,'.','') = ccs.ICD10CM and dx.DX_TYPE = '10'
    union
    select distinct dx.*,
           icd9.ccs_mlvl1 as ccs_dxgrpcd, 
           icd9.ccs_mlvl1label as ccs_dxgrp
    from WT_MU_DX dx 
    join GROUSE_DB.GROUPER_VALUESETS.ICD9DX_CCS icd9 
    on rpad(replace(dx.DX,'.',''),5,'0') = icd9.ICD9 and dx.DX_TYPE = '09'
)
select distinct
       patid,
       encounterid,
       enc_type,
       ccs_dxgrpcd,
       ccs_dxgrp,
       dx_date as ccs_date
from cte_ccs
;

select count(distinct patid) from WT_MU_DX_CCS;
-- 57133

create or replace table WT_MU_PX as
select a.patid
      ,px.encounterid
      ,px.enc_type
      ,px.px
      ,px.px_type
      ,px.px_date
from WT_MU_EHR_ELIG_TBL2 a 
join GROUSE_DB.CMS_PCORNET_CDM.LDS_PROCEDURES px 
on a.patid = px.patid
union
select a.patid
      ,px.encounterid
      ,px.enc_type
      ,px.px
      ,px.px_type
      ,px.px_date
from WT_MU_EHR_ELIG_TBL2 a 
join GROUSE_DB.PCORNET_CDM_MU.LDS_PROCEDURES px 
on a.patid = px.patid
;
select count(distinct patid) from WT_MU_PX;
-- 57133

create or replace table WT_MU_PX_CCS as
with cte_ccs as (
    select b.*, a.ccslvl::varchar as ccs_pxgrpcd, a.ccslvl_label as ccs_pxgrp
    from WT_MU_PX b
    join ONTOLOGY.GROUPER_VALUESETS.CPT_CCS a 
    on to_double(b.PX) between to_double(a.cpt_lb) and to_double(a.cpt_ub) 
       and b.PX_TYPE = 'CH' 
       and regexp_like(b.PX,'^[[:digit:]]+$') 
       and regexp_like(a.cpt_lb,'^[[:digit:]]+$')
    union 
    select b.*, a.ccslvl::varchar as ccs_pxgrpcd, a.ccslvl_label as ccs_pxgrp
    from WT_MU_PX b 
    join ONTOLOGY.GROUPER_VALUESETS.CPT_CCS a 
    on b.PX = a.cpt_lb 
       and b.PX_TYPE = 'CH' 
       and not regexp_like(a.cpt_lb,'^[[:digit:]]+$')
    union
    select b.*, a.ccs_slvl1 as ccs_pxgrpcd, a.ccs_slvl1label as ccs_pxgrp
    from WT_MU_PX b 
    join GROUSE_DB.GROUPER_VALUESETS.ICD9PX_CCS a 
    on replace(b.PX,'.','') = a.ICD9 
       and b.PX_TYPE = '09'
    union 
    select b.*, c.ccs_slvl1 as ccs_pxgrpcd, c.ccs_slvl1label as ccs_pxgrp
    from WT_MU_PX b
    join GROUSE_DB.GROUPER_VALUESETS.ICD10PCS_CCS c 
    on b.PX = c.ICD10PCS and b.PX_TYPE = '10'
)
select distinct
       patid,
       encounterid,
       enc_type,
       ccs_pxgrpcd,
       ccs_pxgrp,
       px_date as ccs_date
from cte_ccs
;
select count(distinct patid), count(*) from WT_MU_PX_CCS;
-- 57133	26594539

-- clinical observables from EHR
create or replace table WT_MU_EHR_HX as
with cte_unpvt_num as (
    select patid, measure_date, measure_time, 
        OBS_NAME, OBS_NUM,'NI' as OBS_QUAL,
        case when OBS_NAME in ('SYSTOLIC','DIASTOLIC') then 'mm[Hg]'
                when OBS_NAME = 'HT' then 'in_us'
                when OBS_NAME = 'WT' then 'lb_av'
                when OBS_NAME = 'ORIGINAl_BMI' then 'kg/m2'
                else null
        end as OBS_UNIT
    from (
        select patid, measure_date, measure_time,
                round(systolic) as systolic, 
                round(diastolic) as diastolic, 
                round(ht) as ht, 
                round(wt) as wt, 
                round(original_bmi) as original_bmi
        from GROUSE_DB.PCORNET_CDM_MU.LDS_VITAL
    )
    unpivot (
        OBS_NUM
        for OBS_NAME in (
                systolic, diastolic, ht, wt, original_bmi
        )
    )
    where OBS_NUM is not null and trim(OBS_NUM) <> ''
), cte_unpvt_qual as (
    select patid, measure_date, measure_time, 
        OBS_NAME, NULL as OBS_NUM, OBS_QUAL, NULL as OBS_UNIT
    from (
        select patid, measure_date, measure_time,
        smoking, tobacco, tobacco_type
        from GROUSE_DB.PCORNET_CDM_MU.LDS_VITAL
    ) 
    unpivot (
        OBS_QUAL
        for OBS_NAME in (
                smoking, tobacco, tobacco_type
        )
    )
    where OBS_QUAL is not null and trim(OBS_QUAL) <> '' 
    and OBS_QUAL not in ('UN','NI','OT')
)
select  distinct
        a.PATID
        ,b.measure_date as OBS_DATE
        ,'UD' as OBS_CODE_TYPE 
        ,b.OBS_NAME as OBS_CODE
        ,b.OBS_NUM
        ,b.OBS_UNIT
        ,b.OBS_QUAL
        ,b.OBS_NAME
from WT_MU_EHR_ELIG_TBL2 a
join (
    select * from cte_unpvt_num
    union 
    select * from cte_unpvt_qual
) b
on a.patid = b.patid
union 
select  distinct
        a.PATID
        ,coalesce(b.obsclin_start_date, b.obsclin_stop_date) as OBS_DATE
        ,b.obsclin_type as OBS_CODE_TYPE
        ,b.obsclin_code as OBS_CODE
        ,b.obsclin_result_num as OBS_NUM
        ,b.obsclin_result_unit as OBS_UNIT
        ,coalesce(trim(b.obsclin_result_qual),trim(b.obsclin_result_text)) as OBS_QUAL
        ,coalesce(b.raw_obsclin_name, c.long_common_name) as OBS_NAME
from WT_MU_EHR_ELIG_TBL2 a
join GROUSE_DB.PCORNET_CDM_MU.LDS_OBS_CLIN b
    on a.patid = b.patid
left join ONTOLOGY.LOINC.LOINC_V2_17 c
    on b.obsclin_code = c.loinc_num and b.obsclin_type = 'LC'
where obsclin_result_num is not null
    or (
        coalesce(trim(b.obsclin_result_qual),trim(b.obsclin_result_text)) is not null 
        and coalesce(trim(b.obsclin_result_qual),trim(b.obsclin_result_text)) <> '' 
        and coalesce(trim(b.obsclin_result_qual),trim(b.obsclin_result_text)) not in ('UN','NI','OT')
    )
;

select count(distinct patid) from WT_MU_EHR_HX;
-- 57133

select obs_name,count(distinct patid) from WT_MU_EHR_HX
group by obs_name
order by count(distinct patid) desc;

-- SYSTOLIC	57133
-- DIASTOLIC	57133
-- Weight (kg)	57130
-- SpO2	57121
-- Height (cm)	57105
-- BMI	57043
-- Braden Skin Score	54995
-- Mean NIBP	53996
-- WT	53767
-- Glasgow Coma Score Adult/Adoles/Peds	52786
-- HT	52351
-- Characteristics of Speech	49285
-- Characteristics of Cough	49075
-- Height (Inches Calc)	48676
-- Oxygen Flow Rate (L/min)	48313
-- Oral Intake	47670
-- Infectious Symptoms Screen	47577
-- Urine Voided (Output)	46442
-- Skin Turgor	46110
-- Smokeless Tobacco	45999
-- ORIGINAL_BMI	45698
-- FiO2 (.21-1.00)	45531
-- Weight (Lbs Calc)	42974
-- Wounds Drainage:	41174
-- Anterior Right Upper Breath Sounds	36901
-- Anterior Left Upper Breath Sounds	36896
-- Severity of Retractions	36338
-- Height (inches)	36330
-- Temperature (Fahrenheit Calc)	36176
-- Urine Cath Output	35973
-- Cough Reflex	35907
-- Anterior Right Lower Breath Sounds	33431
-- ANES SPO2	32088
-- ANES Oxygen Flow Rate (L/min)	31972
-- ANES DBP NIBP	31910
-- ANES SBP NIBP	31877
-- ANES Mean NIBP	31479
-- Most Recent BMI	30487
-- ANES Inspired O2	29696
-- Tobacco Score	29480
-- BSA DuBois	29447
-- ANES Respiratory Rate Vent Setting	29408
-- Primary Fluids Vol Infused (Intake)	28525
-- ANES Tidal Volume	28344
-- ANES Respiratory Rate:  ETCO2	25831
-- ANES Medical Air Flow Rate	24636
-- Respiratory Assessment Severity Score	20170
-- Spontaneous Cough (Respiratory Score)	19704
-- ANES Urine Output	17677
-- ANES Heart Rate Source EKG	16346
-- Breath Sounds RT	15078
-- Incentive Spirometry Volume Achieved	14150
-- Dosing Weight (kg)	14002
-- Edema Location	13679
-- What pain score do you want us to treat	13588
-- Abdominal Assessment	13299
-- Ideal Body Weight Calculated	13174
-- Blood Pressure Systolic	12223
-- Blood Pressure Diastolic	12039
-- HR Supine	12014
-- HR Standing	11990
-- MAP Arterial	11081
-- SBP Arterial	11044
-- O2 Delivery Device	10978
-- Peep/CPAP Set	10937
-- DBP Arterial	10922
-- Volume Exhaled	10915
-- Minute Ventilation	10772
-- HR Sitting Upright	10770
-- Past Medical History	10117


select obs_qual, count(distinct patid) from WT_MU_EHR_HX 
where obs_name = 'Characteristics of Cough'
group by obs_qual;