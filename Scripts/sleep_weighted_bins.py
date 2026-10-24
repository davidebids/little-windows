"""Scoped exact fast path for repeated scalar weighted bin percentiles.

The native weighted percentile remains the fallback. Only finite float64,
positive-weight, one-dimensional columns and the standard 255-bin grid use
this NumPy specialization. No installed dependency files are modified.
"""
from contextlib import contextmanager
import threading
import numpy as np

RANKS = np.linspace(0,100,256)[1:-1]
INDEX = {float(p):i for i,p in enumerate(RANKS)}


def grid_values(array,weights):
    # Match the native helper's second sort of the already-sorted bin column.
    order=np.argsort(array,stable=False)
    x,w=array[order],weights[order]
    cdf=np.cumsum(w)
    threshold=RANKS/100*cdf[-1]
    zero=threshold==0
    threshold[zero]=np.nextafter(threshold[zero],threshold[zero]+1)
    index=np.clip(np.searchsorted(cdf,threshold),0,len(x)-1)
    following=np.minimum(index+1,len(x)-1)
    return np.where(cdf[index]-threshold>np.finfo(np.float64).eps,
                    x[index],(x[index]+x[following])/2)


@contextmanager
def fast_weighted_bins(enabled=True):
    if not enabled:
        yield
        return
    from sklearn.ensemble._hist_gradient_boosting import binning
    original=binning._weighted_percentile
    local=threading.local()
    def percentile(array,weights,percentile_rank=50,average=False,xp=None):
        rank=INDEX.get(float(percentile_rank)) if np.ndim(percentile_rank)==0 else None
        if average and xp is None and rank is not None:
            old=getattr(local,'state',None)
            if old is not None and old[0] is array and old[1] is weights:
                return old[2][rank]
            if (isinstance(array,np.ndarray) and isinstance(weights,np.ndarray)
                and array.ndim==weights.ndim==1 and array.shape==weights.shape and len(array)>0
                and array.dtype==weights.dtype==np.dtype('float64')
                and np.isfinite(array).all() and np.isfinite(weights).all() and (weights>0).all()):
                values=grid_values(array,weights)
                local.state=(array,weights,values)
                return values[rank]
        return original(array,weights,percentile_rank,average=average,xp=xp)
    binning._weighted_percentile=percentile
    try:
        yield
    finally:
        binning._weighted_percentile=original
