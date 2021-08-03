const std = @import("std");
const expect = std.testing.expect;

const lizp = @import("lizp.zig");
const LizpExp = lizp.LizpExp;
const LizpErr = lizp.LizpErr;
const LizpEnv = lizp.LizpEnv;

pub fn evalIfForm(arg_forms: []const LizpExp, env: LizpEnv) LizpErr!LizpExp {
    if (arg_forms.len <= 2) return LizpErr.NotEnoughArguments;
    const test_form = arg_forms[0];
    const test_eval = try lizp.eval(test_form, env);
    switch (test_eval) {
        LizpExp.Bool => {
            const selected_form_idx: usize = if (test_eval.Bool) 1 else 2;
            const selected_form = arg_forms[selected_form_idx];
            return lizp.eval(selected_form, env);
        },
        else => return LizpErr.UnexpectedForm,
    }
}

pub fn evalDefForm(arg_forms: []const LizpExp, env: LizpEnv) LizpErr!LizpExp {
    var mut_env = env;
    if (arg_forms.len <= 1) return LizpErr.NotEnoughArguments;
    if (arg_forms.len >= 3) return LizpErr.UnexpectedForm;
    const key_form = arg_forms[0];
    if (key_form != LizpExp.Symbol) return LizpErr.NotASymbol;
    const evaled_value_form = try lizp.eval(arg_forms[1], env);
    _ = try mut_env.data.put(key_form.Symbol, evaled_value_form);
    return key_form;
}

test "evalIfForm true" {
    const parse = @import("parse.zig").parse;
    const tokenize = @import("tokenize.zig").tokenize;
    const input = "(true 17 34)";
    const expression = try parse(try tokenize(input));
    const env = try lizp.defaultEnv();
    const out = try evalIfForm(expression.List, env);
    try expect(out.Number == 17);
}

test "evalIfForm false" {
    const parse = @import("parse.zig").parse;
    const tokenize = @import("tokenize.zig").tokenize;
    const input = "(false 17 34)";
    const expression = try parse(try tokenize(input));
    const env = try lizp.defaultEnv();
    const out = try evalIfForm(expression.List, env);
    try expect(out.Number == 34);
}
