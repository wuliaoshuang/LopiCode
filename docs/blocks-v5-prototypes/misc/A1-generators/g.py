def nat(emit):
    i = 1
    while True:
        if not emit(i): return
        i += 1
def iter_map(src, f): return lambda emit: src(lambda v: emit(f(v)))
def iter_filter(src, f): return lambda emit: src(lambda v: emit(v) if f(v) else True)
def iter_take(src, n):
    def run(emit):
        k = [0]
        if n <= 0: return
        def step(v):
            k[0] += 1
            if not emit(v): return False
            return k[0] < n
        src(step)
    return run
def first_over(src, limit):
    box = [False, None]
    def step(v):
        if v > limit:
            box[0] = True; box[1] = v; return False
        return True
    src(step)
    return box[1] if box[0] else None
out = []
def collect(v): out.append(v); return True
iter_take(iter_filter(iter_map(nat, lambda x: x * x), lambda x: x % 2 == 1), 4)(collect)
print(",".join(str(v) for v in out), first_over(iter_map(nat, lambda x: x * 3), 10))
