pragma circom 2.0.0;

/////////////////////////////////////////////////////////////////////////////////////
/////////////////////// Templates from the circomlib ////////////////////////////////
////////////////// Copy-pasted here for easy reference //////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////

/*
 * Outputs `a` AND `b`
 */
template AND() {
    signal input a;
    signal input b;
    signal output out;

    out <== a*b;
}

/*
 * Outputs `a` OR `b`
 */
template OR() {
    signal input a;
    signal input b;
    signal output out;

    out <== a + b - a*b;
}

/*
 * `out` = `cond` ? `L` : `R`
 */
template IfThenElse() {
    signal input cond;
    signal input L;
    signal input R;
    signal output out;

    out <== cond * (L - R) + R;
}

/*
 * (`outL`, `outR`) = `sel` ? (`R`, `L`) : (`L`, `R`)
 */
template Switcher() {
    signal input sel;
    signal input L;
    signal input R;
    signal output outL;
    signal output outR;

    signal aux;

    aux <== (R-L)*sel;
    outL <==  aux + L;
    outR <== -aux + R;
}

/*
 * Decomposes `in` into `b` bits, given by `bits`.
 * Least significant bit in `bits[0]`.
 * Enforces that `in` is at most `b` bits long.
 */
template Num2Bits(b) {
    signal input in;
    signal output bits[b];

    for (var i = 0; i < b; i++) {
        bits[i] <-- (in >> i) & 1;
        bits[i] * (1 - bits[i]) === 0;
    }
    var sum_of_bits = 0;
    for (var i = 0; i < b; i++) {
        sum_of_bits += (2 ** i) * bits[i];
    }
    sum_of_bits === in;
}

/*
 * Reconstructs `out` from `b` bits, given by `bits`.
 * Least significant bit in `bits[0]`.
 */
template Bits2Num(b) {
    signal input bits[b];
    signal output out;
    var lc = 0;

    for (var i = 0; i < b; i++) {
        lc += (bits[i] * (1 << i));
    }
    out <== lc;
}

/*
 * Checks if `in` is zero and returns the output in `out`.
 */
template IsZero() {
    signal input in;
    signal output out;

    signal inv;

    inv <-- in!=0 ? 1/in : 0;

    out <== -in*inv +1;
    in*out === 0;
}

/*
 * Checks if `in[0]` == `in[1]` and returns the output in `out`.
 */
template IsEqual() {
    signal input in[2];
    signal output out;

    component isz = IsZero();

    in[1] - in[0] ==> isz.in;

    isz.out ==> out;
}

/*
 * Checks if `in[0]` < `in[1]` and returns the output in `out`.
 */
template LessThan(n) {
    assert(n <= 252);
    signal input in[2];
    signal output out;

    component n2b = Num2Bits(n+1);

    n2b.in <== in[0]+ (1<<n) - in[1];

    out <== 1-n2b.bits[n];
}

/////////////////////////////////////////////////////////////////////////////////////
///////////////////////// Templates for this lab ////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////

/*
 * Outputs `out` = 1 if `in` is at most `b` bits long, and 0 otherwise.
 */
template CheckBitLength(b) {
    assert(b < 254);
    signal input in;
    signal output out;

    component lt = LessThan(b+1);
    lt.in[0] <== in;
    lt.in[1] <== 1 << b;

    out <== lt.out;
}

/*
 * Enforces the well-formedness of an exponent-mantissa pair (e, m), which is defined as follows:
 * if `e` is zero, then `m` must be zero
 * else, `e` must be at most `k` bits long, and `m` must be in the range [2^p, 2^p+1)
 */
template CheckWellFormedness(k, p) {
    signal input e;
    signal input m;

    // check if `e` is zero
    component is_e_zero = IsZero();
    is_e_zero.in <== e;

    // Case I: `e` is zero
    //// `m` must be zero
    component is_m_zero = IsZero();
    is_m_zero.in <== m;

    // Case II: `e` is nonzero
    //// `e` is `k` bits
    component check_e_bits = CheckBitLength(k);
    check_e_bits.in <== e;
    //// `m` is `p`+1 bits with the MSB equal to 1
    //// equivalent to check `m` - 2^`p` is in `p` bits
    component check_m_bits = CheckBitLength(p);
    check_m_bits.in <== m - (1 << p);

    // choose the right checks based on `is_e_zero`
    component if_else = IfThenElse();
    if_else.cond <== is_e_zero.out;
    if_else.L <== is_m_zero.out;
    //// check_m_bits.out * check_e_bits.out is equivalent to check_m_bits.out AND check_e_bits.out
    if_else.R <== check_m_bits.out * check_e_bits.out;

    // assert that those checks passed
    if_else.out === 1;
}

/*
 * Right-shifts `b`-bit long `x` by `shift` bits to output `y`, where `shift` is a public circuit parameter.
 */
template RightShift(b, shift) {
    assert(shift < b);
    signal input x;
    signal output y;

    component x_n2b = Num2Bits(b);
    x_n2b.in <== x;

    component y_b2n = Bits2Num(b);
    for (var i = 0; i < b - shift; i++) {
        y_b2n.bits[i] <== x_n2b.bits[i+shift];
    }
    for (var i = b - shift; i < b; i++) {
        y_b2n.bits[i] <== 0;
    }
    y <== y_b2n.out;
}

/*
 * Rounds the input floating-point number and checks to ensure that rounding does not make the mantissa unnormalized.
 * Rounding is necessary to prevent the bitlength of the mantissa from growing with each successive operation.
 * The input is a normalized floating-point number (e, m) with precision `P`, where `e` is a `k`-bit exponent and `m` is a `P`+1-bit mantissa.
 * The output is a normalized floating-point number (e_out, m_out) representing the same value with a lower precision `p`.
 */
template RoundAndCheck(k, p, P) {
    signal input e;
    signal input m;
    signal output e_out;
    signal output m_out;
    assert(P > p);

    // check if no overflow occurs
    component if_no_overflow = LessThan(P+1);
    if_no_overflow.in[0] <== m;
    if_no_overflow.in[1] <== (1 << (P+1)) - (1 << (P-p-1));
    signal no_overflow <== if_no_overflow.out;

    var round_amt = P-p;
    // Case I: no overflow
    // compute (m + 2^{round_amt-1}) >> round_amt
    var m_prime = m + (1 << (round_amt-1));
    //// Although m_prime is P+1 bits long in no overflow case, it can be P+2 bits long
    //// in the overflow case and the constraints should not fail in either case
    component right_shift = RightShift(P+2, round_amt);
    right_shift.x <== m_prime;
    var m_out_1 = right_shift.y;
    var e_out_1 = e;

    // Case II: overflow
    var e_out_2 = e + 1;
    var m_out_2 = (1 << p);

    // select right output based on no_overflow
    component if_else[2];
    for (var i = 0; i < 2; i++) {
        if_else[i] = IfThenElse();
        if_else[i].cond <== no_overflow;
    }
    if_else[0].L <== e_out_1;
    if_else[0].R <== e_out_2;
    if_else[1].L <== m_out_1;
    if_else[1].R <== m_out_2;
    e_out <== if_else[0].out;
    m_out <== if_else[1].out;
}

/*
 * Left-shifts `x` by `shift` bits to output `y`.
 * Enforces 0 <= `shift` < `shift_bound`.
 * If `skip_checks` = 1, then we don't care about the output and the `shift_bound` constraint is not enforced.
 */
template LeftShift(shift_bound) {
    signal input x;
    signal input shift;
    signal input skip_checks;
    signal output y;

    component lt = LessThan(252);
    lt.in[0] <== shift;
    lt.in[1] <== shift_bound;

    (1 - lt.out) * (1 - skip_checks) === 0;

    // y <==  (x << shift);

    var exponent = 0;
    component isEqual[shift_bound];
    for (var i = 0; i < shift_bound; i++) {
        isEqual[i] = IsEqual();
        isEqual[i].in[0] <== i;
        isEqual[i].in[1] <== shift;
        exponent += isEqual[i].out * (1<<i);
    }

    y <== x * exponent;
}

/*
 * Find the Most-Significant Non-Zero Bit (MSNZB) of `in`, where `in` is assumed to be non-zero value of `b` bits.
 * Outputs the MSNZB as a one-hot vector `one_hot` of `b` bits, where `one_hot`[i] = 1 if MSNZB(`in`) = i and 0 otherwise.
 * The MSNZB is output as a one-hot vector to reduce the number of constraints in the subsequent `Normalize` template.
 * Enforces that `in` is non-zero as MSNZB(0) is undefined.
 * If `skip_checks` = 1, then we don't care about the output and the non-zero constraint is not enforced.
 */
template MSNZB(b) {
    signal input in;
    signal input skip_checks;
    signal output one_hot[b];

    component lt = LessThan(b);
    lt.in[0] <== 0;
    lt.in[1] <== in;

    component or = OR();
    or.a <== skip_checks;
    or.b <== lt.out;
    or.out === 1;

    component n2b = Num2Bits(b);
    n2b.in <== in;

    signal mask[b];
    mask[b-1] <== 1;
    for (var i = b - 2; i >= 0; i--) {
        mask[i] <== mask[i+1] * (1 - n2b.bits[i+1]);
    }

    for (var i = 0; i < b; i++) {
        one_hot[i] <== mask[i] * n2b.bits[i];
    }
}

/*
 * Normalizes the input floating-point number.
 * The input is a floating-point number with a `k`-bit exponent `e` and a `P`+1-bit *unnormalized* mantissa `m` with precision `p`, where `m` is assumed to be non-zero.
 * The output is a floating-point number representing the same value with exponent `e_out` and a *normalized* mantissa `m_out` of `P`+1-bits and precision `P`.
 * Enforces that `m` is non-zero as a zero-value can not be normalized.
 * If `skip_checks` = 1, then we don't care about the output and the non-zero constraint is not enforced.
 */
template Normalize(k, p, P) {
    signal input e;
    signal input m;
    signal input skip_checks;
    signal output e_out;
    signal output m_out;
    assert(P > p);

    component msnzb = MSNZB(P+1);
    msnzb.in <== m;
    msnzb.skip_checks <== skip_checks;

    var ell = 0;
    var shift = 0;
    for (var i = 0; i < P+1; i++) {
        // msnzb.out[i] is 1 for just some single i, rest zero
        ell += msnzb.one_hot[i] * i;
        shift += msnzb.one_hot[i] * (1 << (P-i));
    }
    e_out <== e + ell - p;
    m_out <== m * shift;

}

/*
 * Adds two floating-point numbers.
 * The inputs are normalized floating-point numbers with `k`-bit exponents `e` and `p`+1-bit mantissas `m` with scale `p`.
 * Does not assume that the inputs are well-formed and makes appropriate checks for the same.
 * The output is a normalized floating-point number with exponent `e_out` and mantissa `m_out` of `p`+1-bits and scale `p`.
 * Enforces that inputs are well-formed.
 */
template FloatAdd(k, p) {
    signal input e[2];
    signal input m[2];
    signal output e_out;
    signal output m_out;

    var P = 2*p + 1;
    var shift_bound = 252;
    var less_than_bound = 252;
    var skip_checks = 0;

    assert(e[0] != 0 || m[0] == 0);
    assert(m[0] == 0 || m[0] >= 1<<p);
    assert(e[1] != 0 || m[1] == 0);
    assert(m[1] == 0 || m[1] >= 1<<p);

    component cwf[2];
    for(var i = 0; i < 2; i++) {
        cwf[i] = CheckWellFormedness(k, p);
        cwf[i].e <== e[i];
        cwf[i].m <== m[i];
    }

    component left_shift[2];
    var mgn[2];
     for(var i = 0; i < 2; i++) {
        left_shift[i] = LeftShift(shift_bound);
        left_shift[i].x <== e[i];
        left_shift[i].shift <== p+1;
        left_shift[i].skip_checks <== 1;
        mgn[i] = left_shift[i].y + m[i];
    }

    component less_than = LessThan(less_than_bound);
    less_than.in <== mgn;

    component switcher_e = Switcher();
    switcher_e.sel <== less_than.out;
    switcher_e.L <== e[0];
    switcher_e.R <== e[1];
    signal e_alpha <== switcher_e.outL;
    signal e_beta <== switcher_e.outR;
    
    component switcher_m = Switcher();
    switcher_m.sel <== less_than.out;
    switcher_m.L <== m[0];
    switcher_m.R <== m[1];
    signal m_alpha <== switcher_m.outL;
    signal m_beta <== switcher_m.outR;

    var e_diff = e_alpha - e_beta;

    component e_diff_is_greater = LessThan(less_than_bound);
    e_diff_is_greater.in[0] <== p + 1;
    e_diff_is_greater.in[1] <== e_diff;

    component e_alpha_is_zero = IsZero();
    e_alpha_is_zero.in <== e_alpha;

    component or = OR();
    or.a <== e_diff_is_greater.out;
    or.b <== e_alpha_is_zero.out;

    component left_shift_2 = LeftShift(shift_bound);
    left_shift_2.x <== m_alpha * (1 - or.out);
    left_shift_2.shift <== e_diff;
    left_shift_2.skip_checks <== or.out;

    component normalized = Normalize(k, p, P);
    normalized.e <== e_beta;
    normalized.m <== left_shift_2.y + m_beta;
    normalized.skip_checks <== or.out;

    component round_and_check = RoundAndCheck(k, p, P);
    round_and_check.e <== normalized.e_out * (1 - or.out);
    round_and_check.m <== normalized.m_out * (1 - or.out);

    component e_if = IfThenElse();
    e_if.cond <== or.out;
    e_if.L <== e_alpha;
    e_if.R <== round_and_check.e_out;

    component m_if = IfThenElse();
    m_if.cond <== or.out;
    m_if.L <== m_alpha;
    m_if.R <== round_and_check.m_out;

    e_out <== e_if.out;
    m_out <== m_if.out;
}
