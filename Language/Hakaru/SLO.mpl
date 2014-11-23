# SLO = Simplify Linear Operator.
#
#  This assumes that the input is the output of Language.Hakaru.Syntax.tester
# No checking is done that this is actually the case.
#
# SLO : simplifier
# AST : takes simplified form and transform to AST
#

SLO := module ()
  export ModuleApply, AST, simp, c; # very important: this c is "global".
  local ToAST, t_binds, t_pw, into_pw, myprod, gensym, gs_counter;

  t_binds := 'specfunc(anything, {int, Int, sum, Sum})';
  t_pw := 'specfunc(anything, piecewise)';

  ModuleApply := proc(inp::anything) 
    local e;
    try
      simp(inp(c));
    catch "Wrong kind of parameters in piecewise":
      error "Bug in Hakaru -> Maple translation, piecewise used incorrectly.";
    end try;
  end proc;

  # AST transforms the Maple to a representation of the mochastic AST
  AST := proc(inp::anything)
    local cs;
    cs := indets(inp, 'specfunc'(anything,c));
    # deal with trivial input first
    if inp=0 then
        0
    # then deal with 'bad' input
    elif nops(cs) = 0 then
      error "the constant", inp, " is not a measure."
    elif type(inp, `+`) then
      map(AST, SUM(op(inp)))
    else 
      ToAST(inp, {});
    end if;
  end proc;

  # recursive function which does the main translation
  ToAST := proc(e, ctx)
    local a0, a1, var, vars, rng, ee, cof, d, ld, weight, binders,
      v, subst, ivars, ff, newvar;
    if type(e, specfunc(name, c)) then
        return Return(op(e))
    # we might have recursively encountered a hidden 0
    elif (e = 0) then
       return 0
    # we might have done something odd, and there is no x anymore (and not 0)
    elif type(e, 'numeric') then
      error "the constant", e, "is not a measure"
    # invariant: we depend on c
    else
      binders := indets(e, t_binds);
      if binders = {} then
        # this is a 'raw' measure, with no integrals
        vars := indets(e, specfunc(anything, c));
        subst := map(x-> x = op(0,x)[op(x)], vars);
        ivars := map2(op, 2, subst);
        ee := subs(subst, e);
        if type(ee, 'polynom'(anything,ivars)) then
          ee := collect(ee, ivars);
          d := degree(ee, ivars);
          ld := ldegree(ee, ivars);
          cof := [coeffs(ee, ivars, 'v')]; # cof and v are lists
          if (d = 1) and (ld = 1) then
              # WM = Weight-Measure pair
              ff := (x,y) -> WM(simplify(x), op(y));
              Superpose(op(zip(ff, cof, v)));
              # `if`(cof=1, rest, Bind_(Factor(simplify(cof)), rest))
          else
            if (ld = 0) then
              error "non-zero constant encountered as a measure", ee
            else
              error "polynomial in c:", ee
            end if;
          end if;
        elif type(ee, t_pw) then
          error "encountered piecewise, case not done yet"
        else
          error "no binders, but still not a polynomial?", ee
        end if;
      else
        if type(e, 'specfunc'(anything, {'int','Int'})) then
          var, rng := op(op(2,e));
          ee := op(1,e);
          # recognize 'raw' uniform
          if ee = c(var) then
              weight := (op(2,rng)-op(1,rng));
              newvar := gensym('yy');
              rest := Bind(Uniform(op(rng)), newvar, Factor(UnsafeProb(newvar)));
              `if`(weight=1, rest, Bind_(Factor(weight), rest));
          elif rng = -infinity..infinity then
              # should recognize densities here
              Bind(Lebesgue, var,ToAST(ee, ctx))
          else
              Bind(Lebesgue, var=rng, ToAST(ee, ctx))
          end if;
        elif type(e, 'specfunc'(anything, {'sum','Sum'})) then
            error "sums not handled yet"
        else
            error "constants should have been pushed inside already", e
        end if;
      end if;
    end if;
  end proc;

  # simp mostly pushes things in.
  simp := proc(e) 
    local a, b, d;
    if type(e, `+`) then
      map(simp, e)
    elif type(e, `*`) then
      a, b := selectremove(type, e, t_binds);
      # now casesplit on what a is
      if a=1 then  # no binders
        a, b := selectremove(type, e, t_pw);
        if a=1 then # and no piecewise either
          d := expand(b); # probably need to write something less brutal
          if b=d then # nothing happened
            simplify(b)
          else # this might be better
            simp(d)
          end if
        elif type(a, `*`) then
          error "do not know how to multiply 2 pw:", a
        elif type(a, t_pw) then
          into_pw(b, a)
        else
          error "something weird happened:", a, " was supposed to be pw"
        end if
      elif type(a, `*`) then
        error "product of 2 binders?!?", a
      else
        subsop(1=myprod(simp(b),simp(op(1,a))), a)
      end if
    elif type(e, t_binds) then
      subsop(1=simp(op(1,e)), e)
    # need to go into pw even if there is no factor to push in
    elif type(e, t_pw) then
      into_pw(1, e)
    else
      simplify(e)
    end if;
  end;

  into_pw := proc(fact, pw)
    local n, f;

    n := nops(pw);
    f := proc(j)
      if j=n then # last one is special, always a value
        simp(myprod(fact, simp(op(j, pw))))
      elif type(j,'odd') then # a condition
        op(j, pw)
      else # j even
        simp(myprod(fact , simp(op(j, pw))))
      end if;
    end proc;
    piecewise(seq(f(i),i=1..n))
  end proc;

  # myprod takes care of pushing a product inside a `+`
  myprod := proc(a, b)
    if type(b,`+`) then
      map2(myprod, a, b)
    else
      a*b
    end if;
  end proc;

  gs_counter := 0;
  gensym := proc(x::name) gs_counter := gs_counter + 1; x || gs_counter; end proc;
end;
