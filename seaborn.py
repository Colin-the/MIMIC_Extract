"""Lightweight seaborn compatibility shim for notebook execution.

This project notebooks use a small subset of seaborn plotting helpers.
On systems where seaborn is unavailable, this shim provides enough API
to keep notebook execution and visualization generation working.
"""

import numpy as np
import matplotlib.pyplot as plt


def set_style(_style):
    return None


def set_context(_context, font_scale=1.0):
    plt.rcParams.update({"font.size": 10 * float(font_scale)})
    return None


def barplot(x=None, y=None, data=None, hue=None, ax=None, **_kwargs):
    if ax is None:
        ax = plt.gca()
    # Support both seaborn styles: barplot(data=df, x="col", y="col") and barplot(x=array, y=array)
    if data is None:
        if x is None or y is None:
            raise ValueError("barplot requires x and y")
        if hue is None:
            ax.bar([str(v) for v in x], y)
            return ax
        raise NotImplementedError("hue is only supported when data is provided")

    if hue is None:
        grouped = data.groupby(x, dropna=False)[y].mean()
        ax.bar(grouped.index.astype(str), grouped.values)
        return ax

    piv = data.pivot_table(index=x, columns=hue, values=y, aggfunc="mean")
    width = 0.8 / max(1, len(piv.columns))
    base = np.arange(len(piv.index))
    bars = []
    for i, col in enumerate(piv.columns):
        vals = piv[col].values
        b = ax.bar(base + i * width, vals, width=width, label=str(col))
        bars.extend(list(b))
    ax.set_xticks(base + width * (len(piv.columns) - 1) / 2)
    ax.set_xticklabels(piv.index.astype(str))
    if len(piv.columns) > 0:
        ax.legend()
    return ax


def heatmap(data, cmap="coolwarm", center=0, cbar_kws=None, ax=None, **_kwargs):
    if ax is None:
        ax = plt.gca()
    arr = np.asarray(data.values if hasattr(data, "values") else data, dtype=float)
    im = ax.imshow(arr, aspect="auto", cmap=cmap)
    if center is not None:
        vmax = np.nanmax(np.abs(arr - center))
        im.set_clim(center - vmax, center + vmax)
    cbar = plt.colorbar(im, ax=ax)
    if cbar_kws and "label" in cbar_kws:
        cbar.set_label(cbar_kws["label"])
    if hasattr(data, "columns"):
        ax.set_xticks(np.arange(len(data.columns)))
        ax.set_xticklabels([str(c) for c in data.columns], rotation=90)
    if hasattr(data, "index"):
        ax.set_yticks(np.arange(len(data.index)))
        ax.set_yticklabels([str(i) for i in data.index])
    return ax


def kdeplot(x, label=None, warn_singular=False, ax=None, **_kwargs):
    if ax is None:
        ax = plt.gca()
    vals = np.asarray(x, dtype=float)
    vals = vals[np.isfinite(vals)]
    if vals.size == 0:
        return ax
    bins = min(60, max(10, int(np.sqrt(vals.size))))
    ax.hist(vals, bins=bins, density=True, histtype="step", label=label)
    if label:
        ax.legend()
    return ax

