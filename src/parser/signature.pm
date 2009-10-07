# Copyright (C) 2009, The Perl Foundation.
# $Id$

class Perl6::Compiler::Signature;

# This class represents a signature in the compiler. It takes care of
# producing an AST that will generate the signature, based upon all of
# the various bits of information it is provided up to that point. The
# motivation for this is making actions.pm simpler, but also to allow
# the underlying signature construction mechanism to change more easily.
# It will also allow more efficient code generation.

# Note that NQP does not yet support accessing attributes or declaring
# them, so we have a little inline PIR and also we create this class at
# first elsewhere.


# Adds a parameter to the signature.
#  - var_name is the name of the lexical that we bind to, if any
#  - nom_type is the main, nominal type of the parameter
#  - cons_type is (at least for now) a junction of other type constraints
#  - type_captures is a list of any lexical type names bound to the type of
#    the incoming parameter
#  - optional sets if the parameter is optional
#  - slurpy sets if the parameter is slurpy
#  - names is a list of one or more names, if this parameter is a named
#    parameter
# - invocant is set to a true value if the parameter is a method invocant
# - multi_invocant is set to a true value if the parameter should be considered
#   by the multi dispatcher
# - read_type should be one of readonly (the default), rw, copy or ref
# - default should be a PAST::Block that when invoked computes the default
#   value.
method add_parameter(*%new_entry) {
    my @entries := self.entries;
    @entries.push(%new_entry);
}


# Adds an invocant to the signature, if it does not already have one.
method add_invocant() {
    my @entries := self.entries;
    if +@entries == 0 || !@entries[0]<invocant> {
        my $param := Q:PIR{ %r = new ['Hash'] };
        $param<var_name> := "self";
        $param<invocant> := 1;
        $param<multi_invocant> := 1;
        @entries.unshift($param);
    }
}


# Sets the default type of the parameters.
method set_default_parameter_type($type_name) {
    Q:PIR {
        $P0 = find_lex "$type_name"
        setattribute self, '$!default_type', $P0
    }
}


# Sets all parameters without an explicit read type to default to rw.
method set_rw_by_default() {
    my @entries := self.entries;
    for @entries {
        unless $_<read_type> {
            $_<read_type> := 'rw';
        }
    }
}


# Produces an AST for generating a low-level signature object. Optionally can
# instead produce code to generate a high-level signature object.
method ast($high_level?) {
    my $ast     := PAST::Stmts.new();
    my @entries := self.entries;
    my $SIG_ELEM_BIND_CAPTURE       := 1;
    my $SIG_ELEM_BIND_PRIVATE_ATTR  := 2;
    my $SIG_ELEM_BIND_PUBLIC_ATTR   := 4;
    my $SIG_ELEM_SLURPY_POS         := 8;
    my $SIG_ELEM_SLURPY_NAMED       := 16;
    my $SIG_ELEM_SLURPY_BLOCK       := 32;
    my $SIG_ELEM_INVOCANT           := 64;
    my $SIG_ELEM_MULTI_INVOCANT     := 128;
    my $SIG_ELEM_IS_RW              := 256;
    my $SIG_ELEM_IS_COPY            := 512;
    my $SIG_ELEM_IS_REF             := 1024;
    my $SIG_ELEM_IS_OPTIONAL        := 2048;
    
    # Allocate a signature and stick it in a register.
    $ast.push(PAST::Op.new(
        :pasttype('bind'),
        PAST::Var.new( :name('signature'), :scope('register'), :isdecl(1) ),
        PAST::Op.new( :inline('    %r = allocate_signature ' ~ +@entries) )
    ));
    my $sig_var := PAST::Var.new( :name('signature'), :scope('register') );

    # We'll likely also find a register holding a null value helpful to have.
    $ast.push(PAST::Op.new( :inline('    null $P0') ));
    my $null_reg := PAST::Var.new( :name('$P0'), :scope('register') );

    # For each of the parameters, emit a call to add the parameter.
    my $i := 0;
    for @entries {
        # First, compute flags.
        my $flags := 0;
        if $_<optional>              { $flags := $flags + $SIG_ELEM_IS_OPTIONAL; }
        if $_<invocant>              { $flags := $flags + $SIG_ELEM_INVOCANT; }
        if $_<multi_invocant> ne "0" { $flags := $flags + $SIG_ELEM_MULTI_INVOCANT; }
        if $_<slurpy> && !$_<names>  { $flags := $flags + $SIG_ELEM_SLURPY_POS; }
        if $_<slurpy> && $_<names>   { $flags := $flags + $SIG_ELEM_SLURPY_NAMED; }
        if $_<read_type> eq 'rw'     { $flags := $flags + $SIG_ELEM_IS_RW; }
        if $_<read_type> eq 'copy'   { $flags := $flags + $SIG_ELEM_IS_COPY; }

        # Emit op to build signature element.
        $ast.push(PAST::Op.new(
            :inline('    set_signature_elem signature, ' ~ $i ~ ', "' ~
                    $_<var_name> ~ '", ' ~ $flags ~ ', %0, %1, %2, %3'),
            ($_<nom_type> && !$_<slurpy>  ?? $_<nom_type>  !! $null_reg),
            ($_<cons_type>                ?? $_<cons_type> !! $null_reg),
            ($_<names> && !$_<slurpy>     ?? $_<names>     !! $null_reg),
            $null_reg
        ));
        $i := $i + 1;
    }

    return $ast;
}


# Accessor for entries in the signature object.
method entries() {
    Q:PIR {
        %r = getattribute self, '$!entries'
        unless null %r goto have_entries
        %r = new ['ResizablePMCArray']
        setattribute self, '$!entries', %r
      have_entries:
    };
}

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 100
# End:
# vim: expandtab shiftwidth=4:
