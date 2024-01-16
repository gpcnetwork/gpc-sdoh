/*
# Copyright (c) 2021-2025 University of Missouri                   
# Author: Xing Song, xsm7f@umsystem.edu                            
# File: wt-cms-mu-aset.sql                                            
*/
select * from WT_MU_EHR_READMIT_ELIG limit 5;
select * from WT_MU_CCI limit 5;
select * from WT_MU_EHR_ELIG_TBL2 limit 5;
select count(*)*0.01 from WT_MU_EHR_READMIT_ELIG;
-- 1000

create or replace table WT_EHR_MU_ENC_BASE as 
with cte_cci as (
    select a.patid, b.encounterid, 
           a.cci_date, a.code_grp, a.cci_score,
           datediff('day',a.cci_date,b.discharge_date) as days_to_discharge,
           row_number() over (partition by a.patid, b.encounterid, a.code_grp order by a.cci_date) as rn
    from WT_MU_CCI a
    join WT_MU_EHR_READMIT_ELIG b 
    on a.patid = b.patid
    where a.cci_date <= b.discharge_date
), cte_tot as (
    select patid, encounterid, 
           min(days_to_discharge) as days_to_discharge,
           sum(cci_score) as cci_tot
    from cte_cci
    where rn = 1
    group by patid, encounterid
), cte_lowfreq as (
    select drg, count(*) as freq,
           case when count(*)>= 1000 then 'DRG_'||drg
                else 'DRG_OT'
           end as drg_regrp
    from WT_MU_EHR_READMIT_ELIG
    group by drg
), cte_obes as (
    select patid, min(obes_date) as obes_date
    from (
        select patid, bmi_obes1_date as obes_date from WT_MU_EHR_TBL1
        union 
        select patid, dx_date as obes_date from WT_MU_DX
        where dx like '278%' or dx like 'E66%' or dx like 'Z68.3%' or dx like 'Z68.4%'
    )
    group by patid
)
select  distinct 
        dense_rank() over (order by a.patid, a.encounterid) as rowid,
        a.patid, b.patid_acxiom, a.encounterid,
        a.readmit30d_death_ind,
        a.ip_cumcnt_12m,
        case when a.ip_cumcnt_12m >=5  then '>5'
             else '=' || a.ip_cumcnt_12m
        end as ip_cumcnt_12m_cat,
        a.los,
        a.discharge_status,
        case when a.enc_type = 'EI' then 1 else 0 end as ed_ind,
        -- a.discharge_disposition, 
        -- a.admitting_source,
        -- a.admit_date,
        round(datediff('day',b.birth_date,a.admit_date)/365.25) as age_at_enc,
        coalesce(b.sex,d.sex) as sex,
        case when coalesce(d.race,b.race) = '05' then 'WH'
            when coalesce(d.race,b.race) = '03' then 'AA'
            when coalesce(d.race,b.race) = '02' then 'AS'
            when coalesce(d.race,b.race) = '01' then 'AI'
            when coalesce(d.race,b.race) in ('NI','UN') or coalesce(d.race,b.race) is null then 'NI'
            else 'OT'
        end as race,
        case when d.hispanic = 'Y' or b.hispanic = 'Y' then 'Y'
             when d.hispanic = 'N' or b.hispanic = 'N' then 'N'
             else 'NI'
        end as hispanic,
        case when o.obes_date <= a.admit_date then 1 else NULL end as obes,
        NVL(c.CCI_TOT,0) as CCI,
        case when c.CCI_TOT between 1 and 2 then 'CCI1' 
            when c.CCI_TOT between 3 and 4 then 'CCI2'
            when c.CCI_TOT >= 5 then 'CCI3'
            else 'CCI0'
        end as CCI_CLASS,
        -- a.drg,
        coalesce(e.drg_regrp, 'DRG_NI') as drg_regrp
from WT_MU_EHR_READMIT_ELIG a 
join WT_MU_EHR_ELIG_TBL2 b on a.patid = b.patid
left join GROUSE_DB.CMS_PCORNET_CDM.LDS_DEMOGRAPHIC d on a.patid = d.patid
left join cte_obes o on a.patid = o.patid
left join cte_tot c on a.patid = c.patid and a.encounterid = c.encounterid
left join cte_lowfreq e on a.drg = e.drg
;

select count(distinct patid), count(distinct encounterid), count(*) from WT_EHR_MU_ENC_BASE;
-- 50169	104237	104237

select readmit30d_death_ind, count(distinct encounterid)
from WT_EHR_MU_ENC_BASE
group by readmit30d_death_ind;
-- 1	16278
-- 0	87959

select drg_regrp, count(distinct patid) as pat_cnt
from WT_EHR_MU_ENC_BASE
group by drg_regrp 
order by pat_cnt desc;
-- DRG_OT	43201
-- DRG_NI	5137
-- DRG_871	1940
-- DRG_470	1905
-- ...

select hispanic, count(distinct encounterid) as pat_cnt
from WT_EHR_MU_ENC_BASE
group by hispanic;

select CCI, count(distinct patid) as pat_cnt
from WT_EHR_MU_ENC_BASE
group by CCI 
order by CCI;

select * from WT_EHR_MU_ENC_BASE limit 5;
create or replace table WT_EHR_MU_ENC_BASE_LONG as 
with cte_cat as (
    select rowid, patid, encounterid, readmit30d_death_ind,
           var || '_' || val as var, 1 as val 
    from (
        select  rowid,patid,encounterid,readmit30d_death_ind,
                discharge_status,
                sex,
                race,
                hispanic,
                cci_class,
                drg_regrp
        from WT_EHR_MU_ENC_BASE
    )
    unpivot (
        VAL for VAR in (
            discharge_status,
            sex,
            race,
            hispanic,
            cci_class,
            drg_regrp
        )
    )
), cte_num as (
    select *
    from (
    select  rowid,patid,encounterid,readmit30d_death_ind,
            cast(los as number(18,0)) as los,
            cast(age_at_enc as number(18,0)) as age_at_enc,
            cast(obes as number(18,0)) as obes,
            cast(cci as number(18,0)) as cci
    from WT_EHR_MU_ENC_BASE
    )
    unpivot (
        VAL for VAR in (
            los,
            age_at_enc,
            obes,
            cci
        )
    ) 
    where val is not null   
)
select rowid, patid, encounterid, readmit30d_death_ind, var, val from cte_cat 
union 
select rowid, patid, encounterid, readmit30d_death_ind, var, val from cte_num
;

select * from WT_EHR_MU_ENC_BASE_LONG 
-- where val = 0
limit 5;

create or replace table WT_MU_EHR_ELIG_SDOH_S_ORIG as 
select distinct
       a.rowid,
       a.patid, 
       a.encounterid,
       a.readmit30d_death_ind,
       b.sdoh_var,
       b.sdoh_val,
       b.sdoh_type
from WT_EHR_MU_ENC_BASE a  
join WT_MU_EHR_ELIG_SDOH_S b 
on a.patid_acxiom = b.patid
;

select count(distinct patid), count(distinct rowid) from WT_MU_EHR_ELIG_SDOH_S_ORIG
where sdoh_var = 'ADI_NATRANK';
--45522

select * from WT_MU_EHR_ELIG_SDOH_S_ORIG
where sdoh_var = 'EP_AGE65' and sdoh_val is not null
limit 5;

create or replace table WT_EHR_MU_ENC_BASE_SDOH_S_LONG as 
with cte_sdoh_rep as (
    select distinct 
           a.rowid, a.patid, a.encounterid, a.readmit30d_death_ind, 
           b.sdoh_var as var, b.sdoh_val as val 
    from WT_EHR_MU_ENC_BASE a 
    join WT_MU_EHR_ELIG_SDOH_S_NUM b 
    on a.patid_acxiom = b.patid
)
select rowid, patid, encounterid, readmit30d_death_ind, var, val from WT_EHR_MU_ENC_BASE_LONG 
union 
select rowid, patid, encounterid, readmit30d_death_ind, var, val from cte_sdoh_rep
;

select count(distinct patid), count(distinct encounterid) from WT_EHR_MU_ENC_BASE_SDOH_S_LONG;
-- 45625	92065

select * from WT_MU_EHR_ELIG_SDOH_I 
-- where sdoh_val is null
limit 5;

create or replace table WT_MU_EHR_ELIG_SDOH_I_ORIG as 
select distinct
       a.rowid,
       a.patid, 
       a.encounterid,
       a.readmit30d_death_ind,
       b.sdoh_var,
       b.sdoh_val,
       b.sdoh_type
from WT_EHR_MU_ENC_BASE a 
join WT_MU_EHR_ELIG_SDOH_I b 
on a.patid = b.patid
;

select count(distinct patid), count(distinct encounterid) from WT_MU_EHR_ELIG_SDOH_I_ORIG
where sdoh_var = 'H_ASSESSED_VALUE'
;

create or replace table WT_EHR_MU_ENC_BASE_SDOH_I_LONG as 
with cte_sdoh_rep as (
    select distinct 
           a.rowid, a.patid, a.encounterid, a.readmit30d_death_ind, 
           b.sdoh_var as var, b.sdoh_val as val 
    from WT_EHR_MU_ENC_BASE a 
    join WT_MU_EHR_ELIG_SDOH_I_NUM b 
    on a.patid = b.patid
)
select rowid, patid, encounterid, readmit30d_death_ind, var, val from WT_EHR_MU_ENC_BASE_LONG 
union 
select rowid, patid, encounterid, readmit30d_death_ind, var, val from cte_sdoh_rep
;
select count(distinct patid),count(distinct encounterid) from WT_EHR_MU_ENC_BASE_SDOH_I_LONG;
-- 45625	92065

create or replace table WT_EHR_MU_ENC_BASE_SDOH_SI_LONG as 
with cte_sdoh_i as (
    select distinct 
           a.rowid, a.patid, a.encounterid, a.readmit30d_death_ind, 
           b.sdoh_var as var, b.sdoh_val as val 
    from WT_EHR_MU_ENC_BASE a 
    join WT_MU_EHR_ELIG_SDOH_I_NUM b 
    on a.patid = b.patid
), cte_sdoh_s as (
    select distinct 
           a.rowid, a.patid, a.encounterid, a.readmit30d_death_ind, 
           b.sdoh_var as var, b.sdoh_val as val 
    from WT_EHR_MU_ENC_BASE a 
    join WT_MU_EHR_ELIG_SDOH_S_NUM b 
    on a.patid_acxiom = b.patid
)
select rowid, patid, encounterid, readmit30d_death_ind, var, val from WT_EHR_MU_ENC_BASE_LONG 
union 
select rowid, patid, encounterid, readmit30d_death_ind, var, val from cte_sdoh_i 
union
select rowid, patid, encounterid, readmit30d_death_ind, var, val from cte_sdoh_s 
;
select count(distinct patid),count(distinct encounterid) from WT_EHR_MU_ENC_BASE_SDOH_SI_LONG;
-- 45625	92065

create or replace table DATA_DICT(
    VAR varchar(50), 
    VAR_LABEL varchar(5000), 
    VAR_DOMAIN varchar(20)
);
-- cci
insert into DATA_DICT
select distinct upper(code_grp),full,'CCI'
from Z_REF_CCI
;
-- drg
insert into DATA_DICT
select distinct lpad(code,3,'0'),lower(description),'DRG'
from Z_REF_DRG
;
-- sdoh-s
insert into DATA_DICT
select VAR, VAR_LABEL, VAR_DOMAIN
from S_SDH_SEL
;
-- sdoh-i
insert into DATA_DICT
select distinct VAR, VAR_LABEL, 'ACXIOM-' || VAR_DOMAIN
from I_SDH_SEL
;

select var_domain, count(distinct var)
from DATA_DICT
group by var_domain
order by var_domain;

-- ACS	57
-- ACXIOM-Children	2
-- ACXIOM-Education	1
-- ACXIOM-Ethnicity	4
-- ACXIOM-Financial	7
-- ACXIOM-Household	12
-- ACXIOM-Income	2
-- ACXIOM-Interests	44
-- ACXIOM-Lifestyle	7
-- ACXIOM-Occupation	3
-- ACXIOM-Other	3
-- ACXIOM-Political	1
-- ACXIOM-Property	11
-- ACXIOM-Vehicle	4
-- ADI	2
-- CCI	17
-- DRG	999
-- FARA	70
-- MUA	1
-- RUCA	2
-- SLM	98
-- SVI	66


create or replace table SUBGRP as 
with cte_dual_lis as(
    select distinct patid, 1 as ind
    from WT_MU_EHR_ELIG_SDOH_I_NUM
    where sdoh_var = 'DUAL_LIS_ELIG'
)
select a.patid, 
       a.encounterid,
       a.rowid,
       coalesce(b.ind,0) as dual_lis, 
       case when a.race <> 'WH' then 1 else 0 end as non_white,
       coalesce(a.obes,0) as obes
from WT_EHR_MU_ENC_BASE a  
left join cte_dual_lis b on a.patid = b.patid
;

select count(distinct encounterid), count(*) from SUBGRP;
select * from SUBGRP limit 5;