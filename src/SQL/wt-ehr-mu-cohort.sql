/*
# Copyright (c) 2021-2025 University of Missouri                   
# Author: Xing Song, xsm7f@umsystem.edu                            
# File: wt-cms-mu-cohort.sql                                            
*/
-- check availability of dependency tables
select * from OVERVIEW.WT_TABLE_LONG limit 5;
select * from OVERVIEW.WT_TABLE1 limit 5;
select * from GROUSE_DB_GREEN.patid_mapping.patid_xwalk_mu limit 5;
select * from SDOH_DB.ACXIOM.DEID_ACXIOM_DATA limit 5; 
select * from SDOH_DB.ACXIOM.MU_GEOID_DEID limit 5;
select * from GROUSE_DB.PCORNET_CDM_MU.LDS_ENCOUNTER limit 5;
select * from GROUSE_DB.PCORNET_CDM_MU.LDS_DIAGNOSIS where pdx = 'P' limit 5;
select * from GROUSE_DB.PCORNET_CDM_MU.LDS_PROCEDURES where ppx = 'P' limit 5;
select * from EXCLD_INDEX;
select * from EXCLD_PLANNED; 

create or replace table WT_MU_EHR_TBL1 as 
with cte_obes as (
    select patid,
           measure_num as bmi,
           measure_date as bmi_date,
           row_number() over (partition by patid order by bmi_date) as rn
    from OVERVIEW.WT_TABLE_LONG
    where site = 'MU' and 
          measure_type = 'BMI' and
          measure_num between 30 and 200
), cte_obes_1st as (
    select * from cte_obes
    where rn = 1
), cte_obswin as (
    select patid, 
           min(ENR_START_DATE) as ENR_START, 
           max(ENR_END_DATE) as ENR_END
    from GROUSE_DB.CMS_PCORNET_CDM.LDS_ENROLLMENT 
    group by patid
), cte_dedup as (
    select  a.PATID,
            a.birth_date,
            a.SEX,
            a.RACE,
            a.HISPANIC,
            a.HT,
            a.BMI as BMI1,
            a.INDEX_DATE as BMI1_DATE,
            a.AGE_AT_INDEX as AGE_AT_BMI1,
            a.AGEGRP_AT_INDEX as AGEGRP_AT_BMI1,
            o.ENR_START,
            round(datediff('day',a.BIRTH_DATE,o.ENR_START)/365.25) as AGE_AT_ENR_START,
            o.ENR_END,
            datediff('day',o.ENR_START,o.ENR_END) as ENR_DUR,
            datediff('day',o.ENR_START,a.INDEX_DATE) as DAYS_ENR_TO_BMI1,
            b.bmi as BMI_OBES1,
            b.bmi_date as BMI_OBES1_DATE,
            c.patid as PATID_ACXIOM,
            row_number() over (partition by a.patid order by datediff('day',o.ENR_START,o.ENR_END)) as rn
        from OVERVIEW.WT_TABLE1 a 
        join cte_obswin o on a.patid = o.patid
        join GROUSE_DB_GREEN.patid_mapping.patid_xwalk_mu d on a.patid = d.patid_hash
        join SDOH_DB.ACXIOM.DEID_ACXIOM_DATA c on d.patid = c.patid 
        join SDOH_DB.ACXIOM.MU_GEOID_DEID m on c.patid = m.patid
        left join cte_obes_1st b on a.patid = b.patid
        where a.AGE_AT_INDEX >= 18
)
select PATID,
       BIRTH_DATE,
       SEX,
       RACE,
       HISPANIC,
       AGE_AT_ENR_START,
       ENR_START,
       ENR_END,
       ENR_DUR,
       HT,
       BMI1,
       BMI1_DATE
       BMI_OBES1,
       BMI_OBES1_DATE,
       PATID_ACXIOM
from cte_dedup 
where rn = 1
;

select count(distinct patid), count(*) from WT_MU_EHR_TBL1;

-- encounter cohort
create or replace table WT_MU_EHR_ADMIT as 
with cte_cnsr as (
    select patid, max(censor_date) as censor_date
    from (
        select patid, max(enr_end_date) as censor_date 
        from GROUSE_DB.CMS_PCORNET_CDM.LDS_ENROLLMENT
        group by patid
        union 
        select patid, max(coalesce(discharge_date,admit_date)) as censor_date
        from GROUSE_DB.PCORNET_CDM_MU.LDS_ENCOUNTER
        group by patid
    )
    group by patid
),  cte_death as (
    select patid, max(death_date) as death_date
    from (
        select patid, death_date 
        from GROUSE_DB.CMS_PCORNET_CDM.LDS_DEATH
        union 
        select patid, death_date
        from GROUSE_DB.PCORNET_CDM_MU.LDS_DEATH
    )
    group by patid
)
select  distinct
        a.patid,
        a.enr_end,
        b.encounterid,
        b.enc_type,
        case when length(trim(b.drg)) > 3 then LTRIM(b.drg,'0') 
            when length(trim(b.drg)) < 3 then LPAD(b.drg,3,'0')
            else trim(b.drg) 
        end as drg,
        b.admit_date,
        b.discharge_date,
        b.admitting_source,
        b.discharge_status,    
        b.discharge_disposition,
        p.provider_npi,
        d.death_date,
        s.censor_date,
        1 as ip_counter
from WT_MU_EHR_TBL1 a 
join GROUSE_DB.PCORNET_CDM_MU.LDS_ENCOUNTER b on a.patid = b.patid
left join GROUSE_DB.PCORNET_CDM_MU.LDS_PROVIDER p on b.PROVIDERID = p.PROVIDERID
left join cte_death d on a.patid = d.patid
left join cte_cnsr s on s.patid = a.patid
where b.enc_type in ('IP','EI')
order by a.patid, b.admit_date
;

select count(distinct patid), count(distinct encounterid) from WT_MU_EHR_ADMIT;
-- 71878	208993

create or replace table WT_MU_EHR_READMIT as
with cte_lag as (
    select patid,
        censor_date,
        encounterid,
        lead(encounterid) over (partition by patid order by admit_date) as encounterid_lead,
        enc_type,
        drg,
        lead(enc_type) over (partition by patid order by admit_date) as enc_type_lead,
        lead(drg) over (partition by patid order by admit_date) as drg_lead,
        admit_date,
        lead(admit_date) over (partition by patid order by admit_date) as admit_date_lead,
        admitting_source,
        lead(admitting_source) over (partition by patid order by admit_date) as admitting_source_lead, 
        discharge_date,
        discharge_status,
        discharge_disposition,
        provider_npi,
        lead(provider_npi) over (partition by patid order by admit_date) as provider_npi_lead, 
        death_date
    from WT_MU_EHR_ADMIT
), cte_readmit as (
    select l.*,
           coalesce(nullifzero(datediff('day',l.admit_date,l.discharge_date)),1) as los,
           datediff('day',l.discharge_date,l.admit_date_lead) as days_disch_to_lead,
           datediff('day',l.discharge_date,l.censor_date) as days_disch_to_censor,
           datediff('day',l.discharge_date,l.death_date) as days_disch_to_death
    from cte_lag l
    where days_disch_to_lead > 0 or days_disch_to_lead is null
), cte_cumcnt as (
    select a.patid, a.encounterid, 
           count(distinct b.admit_date) over (partition by a.patid, a.encounterid) as ip_cumcnt_12m,
           row_number() over (partition by a.patid, a.encounterid order by b.admit_date) as rn
    from WT_MU_EHR_ADMIT a 
    join WT_MU_EHR_ADMIT b 
    on a.patid = b.patid
    where b.admit_date < a.admit_date and b.admit_date >= dateadd(month,-12,a.admit_date)
)
select a.patid,
       a.encounterid,
       a.encounterid_lead,
       a.enc_type,
       a.drg,
       a.admit_date,
       a.admitting_source,
       a.discharge_date,
       a.discharge_status,
       a.discharge_disposition,
       a.los,
       a.provider_npi,
       a.days_disch_to_lead, 
       a.enc_type_lead,
       a.drg_lead,
       a.provider_npi_lead,
       a.days_disch_to_censor,
       a.days_disch_to_death,
       b.ip_cumcnt_12m
from cte_readmit a 
left join cte_cumcnt b 
on a.patid = b.patid and a.encounterid = b.encounterid and b.rn = 1
;

select * from WT_MU_EHR_READMIT 
order by patid, admit_date
limit 50;

select count(distinct patid), count(distinct encounterid) from WT_MU_EHR_READMIT;
-- 71878	198569 

create or replace table WT_MU_EHR_ELIG_TBL1 as
select a.* 
from WT_MU_EHR_TBL1 a 
where exists (
    select 1 from WT_MU_EHR_READMIT b
    where a.patid = b.patid
)
;
select count(distinct patid), count(*) from WT_MU_EHR_ELIG_TBL1;
-- 71878

create or replace table WT_MU_EHR_PDX as 
select a.patid
      ,dx.encounterid
      ,dx.enc_type
      ,dx.dx
      ,dx.dx_type
      ,dx.dx_date
from WT_MU_EHR_ELIG_TBL1 a 
join GROUSE_DB.PCORNET_CDM_MU.LDS_DIAGNOSIS dx 
on a.patid = dx.patid
where dx.pdx = 'P'
;
select * from WT_MU_EHR_PDX limit 5;

create or replace table WT_MU_EHR_PPX as
select a.patid
      ,px.encounterid
      ,px.enc_type
      ,px.px
      ,px.px_type
      ,px.px_date
from WT_MU_EHR_ELIG_TBL1 a 
join GROUSE_DB.PCORNET_CDM_MU.LDS_PROCEDURES px 
on a.patid = px.patid
where px.ppx = 'P'
;
select * from WT_MU_EHR_PPX limit 5;

-- excld: <= 30 days
select count(distinct patid), count(distinct encounterid) from WT_MU_EHR_READMIT
where least(coalesce(days_disch_to_death,days_disch_to_censor),days_disch_to_censor) <= 30;
-- 13932	16330

-- excld: expired at discharge
select count(distinct patid), count(distinct encounterid) from WT_MU_EHR_READMIT
where discharge_disposition = 'E' or discharge_status = 'EX';
-- 4430	4430

-- excld: against medical advice
select count(distinct patid), count(distinct encounterid) from WT_MU_EHR_READMIT
where discharge_status = 'AM';
-- 899	1193

-- excld: transfer to another acute care hospital
select count(distinct patid), count(distinct encounterid) from WT_MU_EHR_READMIT
where discharge_status in ('SH','IP');
-- 2708	3205

-- excld: primary psychiatric diagnoses 
-- excld: medical treatment of cancer
insert into EXCLD_INDEX
select 'rehab',254,'Rehabilitation'
;
select * from EXCLD_INDEX;
create or replace table EXCLD_INDEX_CCS_EHR as 
with cte_ccs as (
    select distinct dx.*,
           ccs.ccs_slvl1 as ccs_dxgrpcd, 
           ccs.ccs_slvl1label as ccs_dxgrp
    from WT_MU_EHR_PDX dx 
    join GROUSE_DB.GROUPER_VALUESETS.ICD10CM_CCS ccs 
    on replace(dx.DX,'.','') = ccs.ICD10CM and dx.DX_TYPE = '10'
    union
    select distinct dx.*,
           icd9.ccs_mlvl1 as ccs_dxgrpcd, 
           icd9.ccs_mlvl1label as ccs_dxgrp
    from WT_MU_EHR_PDX dx 
    join GROUSE_DB.GROUPER_VALUESETS.ICD9DX_CCS icd9 
    on rpad(replace(dx.DX,'.',''),5,'0') = icd9.ICD9 and dx.DX_TYPE = '09'
)
select a.patid,
       a.encounterid,
       b.ccs_dxgrpcd,
       c.excld_type,
       c.description
from WT_MU_EHR_READMIT a 
join cte_ccs b on a.patid = b.patid and a.encounterid = b.encounterid 
join EXCLD_INDEX c on b.ccs_dxgrpcd = c.ccs
;
select excld_type, count(distinct patid), count(distinct encounterid) from EXCLD_INDEX_CCS_EHR
group by excld_type;
-- cancer	24089	38184
-- psychiatric	3173	4972
-- rehab	58	84

-- excld: planned readmission
select * from EXCLD_PLANNED;
create or replace table EXCLD_PLANNED_CCS_EHR as 
with cte_ccs_px as (
    select b.*, a.ccslvl::varchar as ccs_pxgrpcd, a.ccslvl_label as ccs_pxgrp
    from WT_MU_EHR_PPX b
    join ONTOLOGY.GROUPER_VALUESETS.CPT_CCS a 
    on to_double(b.PX) between to_double(a.cpt_lb) and to_double(a.cpt_ub) 
       and b.PX_TYPE = 'CH' 
       and regexp_like(b.PX,'^[[:digit:]]+$') 
       and regexp_like(a.cpt_lb,'^[[:digit:]]+$')
    union 
    select b.*, a.ccslvl::varchar as ccs_pxgrpcd, a.ccslvl_label as ccs_pxgrp
    from WT_MU_EHR_PPX b 
    join ONTOLOGY.GROUPER_VALUESETS.CPT_CCS a 
    on b.PX = a.cpt_lb 
       and b.PX_TYPE = 'CH' 
       and not regexp_like(a.cpt_lb,'^[[:digit:]]+$')
    union
    select b.*, a.ccs_slvl1 as ccs_pxgrpcd, a.ccs_slvl1label as ccs_pxgrp
    from WT_MU_EHR_PPX b 
    join GROUSE_DB.GROUPER_VALUESETS.ICD9PX_CCS a 
    on replace(b.PX,'.','') = a.ICD9 
       and b.PX_TYPE = '09'
    union 
    select b.*, c.ccs_slvl1 as ccs_pxgrpcd, c.ccs_slvl1label as ccs_pxgrp
    from WT_MU_EHR_PPX b
    join GROUSE_DB.GROUPER_VALUESETS.ICD10PCS_CCS c 
    on b.PX = c.ICD10PCS and b.PX_TYPE = '10'
), cte_ccs_dx as (
    select distinct dx.*,
           ccs.ccs_slvl1 as ccs_dxgrpcd, 
           ccs.ccs_slvl1label as ccs_dxgrp
    from WT_MU_EHR_PDX dx 
    join GROUSE_DB.GROUPER_VALUESETS.ICD10CM_CCS ccs 
    on replace(dx.DX,'.','') = ccs.ICD10CM and dx.DX_TYPE = '10'
    union
    select distinct dx.*,
           icd9.ccs_mlvl1 as ccs_dxgrpcd, 
           icd9.ccs_mlvl1label as ccs_dxgrp
    from WT_MU_EHR_PDX dx 
    join GROUSE_DB.GROUPER_VALUESETS.ICD9DX_CCS icd9 
    on rpad(replace(dx.DX,'.',''),5,'0') = icd9.ICD9 and dx.DX_TYPE = '09'
)
select a.patid,
       a.encounterid,
       c.ccs,
       c.description
from WT_MU_EHR_READMIT a 
join cte_ccs_px b on a.patid = b.patid and a.encounterid = b.encounterid 
join EXCLD_PLANNED c on b.ccs_pxgrpcd = c.ccs
where c.ccs_type = 'px'
union 
select a.patid,
       a.encounterid,
       c.ccs,
       c.description
from WT_MU_EHR_READMIT a 
join cte_ccs_dx b on a.patid = b.patid and a.encounterid = b.encounterid 
join EXCLD_PLANNED c on b.ccs_dxgrpcd = c.ccs
where c.ccs_type = 'dx'
;
select count(distinct patid), count(distinct encounterid) from EXCLD_PLANNED_CCS_EHR;
-- 34605	52806

create or replace table WT_MU_EHR_READMIT_ELIG as 
select a.*, 
       case when (a.days_disch_to_lead <= 30 and c.ccs is null) or -- non-terminal encounter
                 (a.encounterid_lead is null and a.days_disch_to_death <= 30) -- terminal encounter
       then 1 else 0 
       end as readmit30d_death_ind
from WT_MU_EHR_READMIT a
left join EXCLD_INDEX_CCS_EHR o 
on a.patid = o.patid and a.encounterid = o.encounterid
left join EXCLD_PLANNED_CCS_EHR c 
on a.patid = c.patid and a.encounterid_lead = c.encounterid
-- apply exclusion criteria
where least(coalesce(a.days_disch_to_death,a.days_disch_to_censor),a.days_disch_to_censor) > 30 and 
      a.discharge_disposition not in ('E') and 
      a.discharge_status not in ('AM','EX','IP','SH') and 
      not exists (select 1 from EXCLD_INDEX_CCS_EHR b where a.patid = b.patid and a.encounterid = b.encounterid)
;
select count(distinct patid), count(distinct encounterid), count(*) from WT_MU_EHR_READMIT_ELIG;
-- 50169	104237	104237

select readmit30d_death_ind, count(distinct encounterid)
from WT_MU_EHR_READMIT_ELIG
group by readmit30d_death_ind;
-- 1	16278
-- 0	87959

select * from WT_MU_EHR_READMIT_ELIG 
-- where days_disch_to_death is not null
order by patid, admit_date;

create or replace table WT_MU_EHR_ELIG_TBL2 as
select a.* 
from WT_MU_EHR_TBL1 a 
where exists (
    select 1 from WT_MU_EHR_READMIT_ELIG b
    where a.patid = b.patid
)
;
select count(distinct patid), count(*) from WT_MU_EHR_ELIG_TBL2;
-- 50169

create or replace table WT_MU_EHR_ELIG_GEOID as
select a.*
from SDOH_DB.ACXIOM.MU_GEOID_DEID a
where exists (
    select 1 from WT_MU_EHR_ELIG_TBL2 b 
    where b.patid_acxiom = a.patid
) 
;
select count(distinct patid), count(*) from WT_MU_EHR_ELIG_GEOID;
-- 50169	50874