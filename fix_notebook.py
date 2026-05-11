import nbformat

with open('/home/ccampb47/work/MIMIC_Extract/notebooks/curated_mimic_iii_analysis.ipynb', 'r') as f:
    nb = nbformat.read(f, as_version=4)

for cell in nb.cells:
    if cell.cell_type == 'code' and 'def visualize_centroid_shift' in cell.source:
        source = cell.source
        
        # Replace the compute_centroid call to align columns
        old_code = "cents = {lab: compute_centroid(Xv_agg, pat, lab) for lab in LABELS}"
        new_code = """        # Align columns to baseline
        Xv_agg_aligned = Xv_agg.reindex(columns=X_base_agg.columns)
        cents = {lab: compute_centroid(Xv_agg_aligned, pat, lab) for lab in LABELS}"""
        
        if old_code in source:
            source = source.replace(old_code, new_code)
            cell.source = source
            print("Successfully modified the cell.")
        else:
            print("Could not find the exact code to replace.")

with open('/home/ccampb47/work/MIMIC_Extract/notebooks/curated_mimic_iii_analysis.ipynb', 'w') as f:
    nbformat.write(nb, f)
