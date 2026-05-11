# Vital signs in preprocessed data set
_Exported on 3/24/2026 at 13:02:33 EDT from Cursor (2.6.20)_

---

**User**

Can you examine this repository and determine what vital signs will be present in the data set when the preprocessing is complete

---

**Cursor**


Searching the repository for how vital signs are defined, extracted, and included in the preprocessed dataset.




Here is what the repo actually does and which items count as **vital signs** in the finished product.

## How the pipeline chooses variables

Dynamic series come from `resources/itemid_to_variable_map.csv`. `get_variable_mapping` keeps only rows with a non-empty `LEVEL2`, `COUNT > 0`, and **`STATUS == 'ready'`**:

```152:158:c:\Users\legoc\school\research\MIMIC_Extract\mimic_direct_extract.py
def get_variable_mapping(mimic_mapping_filename):
    # Read in the second level mapping of the itemids
    var_map = pd.read_csv(mimic_mapping_filename, index_col=None)
    var_map = var_map.loc[(var_map['LEVEL2'] != '') & (var_map['COUNT']>0)]
    var_map = var_map.loc[(var_map['STATUS'] == 'ready')]
    var_map['ITEMID'] = var_map['ITEMID'].astype(int)

    return var_map
```

Those item IDs are read from **`chartevents`** and **`labevents`**, standardized and clipped using `variable_ranges.csv`, then aggregated **by hour** and **by `LEVEL2` name** (default: `group_by_level2=True`). Each variable ends up as **mean, std, and count** in the `vitals_labs` table (and means-only in `vitals_labs_mean`).

So the README name is accurate: output is **vitals and labs together**, not “vitals only.”

## Vital signs (and closely related bedside measures) in this mapping

Under the usual ICU sense of **vital signs** plus **very common bedside additions** that appear as `LEVEL2` with **`chartevents`** sources in the ready map:

| Category | `LEVEL2` names in this repo |
|----------|----------------------------|
| **Core vitals** | Heart Rate; Systolic blood pressure; Diastolic blood pressure; Mean blood pressure; Temperature; Respiratory rate; Oxygen saturation |
| **Anthropometrics** | Weight; Height |
| **Neurologic** | Glascow coma scale total *(spelled this way in the CSV)* |
| **Perfusion / exam** | Capillary refill rate |
| **Ventilation & gases** (often used with vitals in ICU ML) | Fraction inspired oxygen; Fraction inspired oxygen Set; Positive end-expiratory pressure; Positive end-expiratory pressure Set; Peak inspiratory pressure; Plateau Pressure; Respiratory rate Set; Tidal Volume Observed / Set / Spontaneous; CO2 (ETCO2, PCO2, etc.); Partial pressure of carbon dioxide; Partial pressure of oxygen; Venous PvO2; pH |
| **Hemodynamics** (lines / monitors) | Central Venous Pressure; Pulmonary Artery Pressure mean; Pulmonary Artery Pressure systolic; Pulmonary Capillary Wedge Pressure; Cardiac Index; Cardiac Output Thermodilution; Cardiac Output fick; Systemic Vascular Resistance |
| **Other** | Post Void Residual |

Many **labs** also have `chartevents` rows in the same map (e.g. Glucose, Sodium, troponins, CBC/chemistry pieces). Those are **not** classic vital signs but **do** appear in the same `vitals_labs` matrix when preprocessing finishes.

## Labs-only `LEVEL2` names (no ready `chartevents` row)

There are **37** `LEVEL2` groups that only come from **`labevents`** in the ready map (examples: several **urine / ascites / pleural / CSF** variants, **Urine output**, some **differential** lines like Eosinophils/Neutrophils, **Phosphate** vs **Phosphorous**, etc.). They are still part of the hourly tensor, but they are **laboratory** channels, not nursing vitals.

## Optional column dropping

If you run with **`--min_percent` > 0**, columns whose **mean** is missing in more than `(100 - min_percent)` percent of rows are **dropped** before write. The **default is `0`**, so nothing is removed for sparsity unless you change that.

---

**Bottom line:** After preprocessing, **classic vital signs** are represented mainly by the **blood pressure trio, HR, RR, SpO2, temperature, weight, height, and GCS** (plus optional **capillary refill**). The **final HDF5 `vitals_labs` group also includes ventilation/hemodynamic monitor variables and a large set of lab analytes** merged into the same hourly feature block, driven entirely by the **106** distinct `LEVEL2` names that survive the `ready` + `COUNT > 0` filter in `itemid_to_variable_map.csv`.

