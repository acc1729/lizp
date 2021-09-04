pub const LizpExp = union(enum) {
    Number: f64,
    Bool: bool,
    Symbol: []const u8,
    List: []const LizpExp,
    Func: fn ([]const LizpExp) LizpErr!*LizpExp,
    Lambda: *LizpLambda,

    // ... Some methods
};

pub const LizpLambda = struct {
    params_exp: *LizpExp,
    body_exp: *LizpExp,
};

pub const LizpEnv = struct {
    data: std.StringHashMap(LizpExp),
    outer: ?*LizpEnv,
};

// Here, we create an instance of LizpExp.Lambda and return it.
pub fn evalFnForm(arg_forms: []const LizpExp) LizpErr!LizpExp {
    if (arg_forms.len <= 1) return LizpErr.NotEnoughArguments;
    if (arg_forms.len >= 3) return LizpErr.UnexpectedForm;
    if (arg_forms[0] != LizpExp.List) return LizpErr.NotAList;
    const lambda = LizpExp{ .Lambda = &lizp.LizpLambda{
        .params_exp = &arg_forms[0],
        .body_exp = &arg_forms[1],
    } };
    // Here, .params_exp and .body_exp are of tag LizpExp.List;
    // Though once we return, we lose the reference to them?
    // Stack pointer decrements, blows up our reference.
    return lambda;
}

// Later on, we stuff the LizpExp.Lambda into a hashmap, env.data
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

// Here, we expect symbols to be the `.params_exp.*` from the LizpExp.Lambda above in evalFnForm,
// which must be LizpExp.List. But mysteriously, it is now LizpExp.Number.
// Changing the tag definition order in LizpExp changes it -- it's always the first defined.
pub fn parseStringsFromSymbols(symbols: LizpExp, alloc: *std.mem.Allocator) LizpErr![][]const u8 {
    if (symbols != LizpExp.List) return LizpErr.NotAList;
    var symbol_strings = std.ArrayList([]const u8).init(alloc);
    for (symbols.List) |symbol| {
        if (symbol != LizpExp.Symbol) return LizpErr.NotASymbol;
        try symbol_strings.append(symbol.Symbol);
    }
    return symbol_strings.items;
}
