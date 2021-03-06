/**
 * Implementation of the
 * $(LINK2 http://www.digitalmars.com/download/freecompiler.html, Digital Mars C/C++ Compiler).
 *
 * Copyright:   Copyright (c) 2006-2017 by Digital Mars, All Rights Reserved
 * Authors:     $(LINK2 http://www.digitalmars.com, Walter Bright)
 * License:     Distributed under the Boost Software License, Version 1.0.
 *              http://www.boost.org/LICENSE_1_0.txt
 * Source:      https://github.com/DigitalMars/Compiler/blob/master/dm/src/dmc/htod.d
 */

module htod;

version (HTOD)
{
import core.stdc.stdio;
import core.stdc.string;
import core.stdc.stdlib;
import core.stdc.ctype;

import dmd.backend.cdef;
import dmd.backend.cc;
import dmd.backend.cgcv;
import dmd.backend.code;
import dmd.backend.el;
import dmd.backend.global;
import dmd.backend.oper;
import dmd.backend.outbuf;
import dmd.backend.ty;
import dmd.backend.type;

import parser;

import dmd.backend.dlist;
import filespec;
import dmd.backend.memh;

extern (C) void crlf(FILE*);

extern (C++):

alias dbg_printf = printf;


/* ======================= cgobj stub ======================================= */

__gshared
{
seg_data **SegData;
}

/* ======================= cgcv stub ======================================= */

void cv_func(Funcsym *s)
{
}

void cv_outsym(Symbol *s)
{
}

idx_t cv4_struct(Classsym *s,int flags)
{
    return 0;
}

/* ======================= objrecor stub ==================================== */

void objfile_open(const(char)* name)
{
}

void objfile_close(void *data, uint len)
{
}

void objfile_delete()
{
}

void objfile_term()
{
}

/* ======================= htod ==================================== */

__gshared
{
mangle_t dlinkage;              // mTYman_xxx
int anylines;
int indent;
int incnest;            // nesting level inside #include's
int sysincnest;         // nesting level inside system #include's
}

void htod_init(const(char)* name)
{
    fprintf(fdmodule, "/* Converted to D from %s by htod */\n", finname);

    char *root = filespecgetroot(name);
    fprintf(fdmodule, "module %s;\n", root);
    mem_free(root);

    dlinkage = mTYman_d;
}

void htod_term()
{
}

bool htod_running()
{
    return true;
}

/*********************
 * Return !=0 if we should output this declaration.
 */

int htod_output()
{
    return incnest == 1 ||
           config.htodFlags & HTODFsysinclude ||
           (config.htodFlags & HTODFinclude && !sysincnest);
}

void htod_indent(int indent)
{   int i;

    for (i = 0; i < indent; i++)
        fprintf(fdmodule, " ");
}

void htod_include(const(char)* p, int flag)
{
    //printf("htod_include('%s', flag = x%x, incnest = %d, sysincnest = %d)\n", p, flag, incnest, sysincnest);
    int inc = htod_output();
    //printf("inc = %d\n", inc);

    incnest++;
    if (sysincnest || flag & FQsystem)
        sysincnest++;

    if (!inc)
        return;

    /* Do not put out import statement if we are
     * drilling down into the #include.
     */
    if (config.htodFlags & HTODFsysinclude ||
        (config.htodFlags & HTODFinclude && !(flag & FQsystem)))
        return;

    char *root = filespecgetroot(p);
    if (flag & FQsystem)
        fprintf(fdmodule, "import std.c.%s;\n", filespecname(root));
    else
        fprintf(fdmodule, "import %s;\n", filespecname(root));
    mem_free(root);
}

void htod_include_pop()
{
    incnest--;
    assert(incnest >= 0);
    if (sysincnest)
        sysincnest--;
}

void htod_writeline()
{
    __gshared const(char)* prefixstring = "//C     ";

    if (htod_output())
    {
        anylines = 1;                   // we've seen some input

        blklst *b;

        b = cstate.CSfilblk;
        if (b)                          /* if data to read              */
        {   char c;
            char *p;
            int prefix;
            __gshared int incomment;
            char *pstart = cast(char *)b.BLtext;

        Lagain:
            prefix = 0;
            for (p = pstart; (c = *p) != 0; p++)
            {
                switch (c)
                {
                    case ' ':
                    case '\t':
                    case '\f':
                    case '\13':
                    case CR:
                    case LF:
                        continue;

                    case '*':
                        if (incomment)
                        {
                            if (p[1] == '/')
                            {
                                incomment = 0;
                                p++;
                                if (!prefix && !(p[1] == 0 || p[1] == '\r' || p[1] == '\n'))
                                {
                                    for (char *q = pstart; q < p + 1; q++)
                                    {   char c2 = *q;
                                        if (c2 != '\n' && c2 != '\r')
                                            fputc(c2, fdmodule);
                                    }
                                    crlf(fdmodule);
                                    fflush(fdmodule);
                                    pstart = p + 1;
                                    goto Lagain;
                                }
                            }
                            continue;
                        }
                        goto L1;

                    case '/':
                        if (p[1] == '/')
                        {
                            break;
                        }
                        if (p[1] == '*')
                        {   incomment = 1;
                            p++;
                            if (prefix)
                            {
                                for (char *q = p + 1; 1; q++)
                                {
                                    if (!*q)
                                    {
                                        if (!(config.htodFlags & HTODFcdecl))
                                        {
                                            fputs(prefixstring, fdmodule);
                                            for (char *s = pstart; s < p - 1; s++)
                                            {   char c2 = *s;
                                                if (c2 != '\n' && c2 != '\r')
                                                    fputc(c2, fdmodule);
                                            }
                                            crlf(fdmodule);
                                            fflush(fdmodule);
                                        }
                                        pstart = p - 1;
                                        incomment = 0;
                                        goto Lagain;
                                    }
                                    if (q[0] == '*' && q[1] == '/')
                                        break;
                                }
                            }
                            continue;
                        }
                        goto L1;

                    default:
                    L1:
                        if (!incomment)
                            prefix = 1;
                        continue;
                }
                break;
            }

            if (!prefix || !(config.htodFlags & HTODFcdecl))
            {
                if (prefix)
                    fputs(prefixstring, fdmodule);

                for (p = pstart; (c = *p) != 0; p++)
                {
                    if (c != '\n' && c != '\r')
                        fputc(c, fdmodule);
                }
                crlf(fdmodule);
                fflush(fdmodule);
            }
        }
    }
}


void htod_define(macro_t *m)
{   char c;

    if (!htod_output() ||
        anylines == 0)
        return;
    if (m.Mflags & (Mfixeddef | Mellipsis | Mkeyword))
        return;
    if (!(m.Mflags & Mnoparen) || !*m.Mtext)
        return;
    //printf("define %s '%s'\n", m.Mid, m.Mtext);

    char *pend;
    strtoull(m.Mtext, &pend, 0);
    c = *pend;
    if (c == 0)
    {
        fprintf(fdmodule, "const %s = %s;\n", &m.Mid[0], m.Mtext);
    }
    else if (pend > m.Mtext && (c == 'u' || c == 'U' || c == 'l' || c == 'L'))
    {   int U = 0;
        int L = 0;
        for (char *p = pend; 1; p++)
        {
            switch (*p)
            {
                case 'u':
                case 'U':
                    if (U)
                        goto Lret;
                    U = 1;
                    continue;

                case 'l':
                case 'L':
                    if (L == 2)
                        goto Lret;
                    L++;
                    continue;

                case 0:
                    break;

                default:
                    goto Lret;  // not recognized
            }
            break;
        }
        fprintf(fdmodule, "const %s = %.*s", &m.Mid[0], pend - m.Mtext, m.Mtext);
        if (U == 1)
            fprintf(fdmodule, "U");
        if (L == 2)
            fprintf(fdmodule, "L");
        fprintf(fdmodule, ";\n");
    }
    else if (isalpha(*m.Mtext) || *m.Mtext == '_')
    {
        for (char *p = m.Mtext; 1; p++)
        {
            c = *p;
            if (!c)
                break;
            if (!isalnum(c) && c != '_')
                goto Lret;
        }
        fprintf(fdmodule, "alias %s %s;\n", m.Mtext, &m.Mid[0]);
    }
    else
    {
        strtold(m.Mtext, &pend);
        c = *pend;
        if (c == 0 ||
            (pend[1] == 0 &&
             (c == 'f' || c == 'F' || c == 'l' || c == 'L')))
        {
            fprintf(fdmodule, "const %s = %s;\n", &m.Mid[0], m.Mtext);
        }
    }
Lret:
    ;
}


void htod_struct(Classsym *s)
{
    struct_t *st;
    symlist_t sl;
    Outbuffer buf;

    st = s.Sstruct;

    uint attr = SFLpublic;
    const(char)* p = "struct";
    if (st.Sflags & STRunion)
        p = "union";
    if (st.Sflags & STRclass)
        p = "class";

    htod_indent(indent);
    fprintf(fdmodule, "%s %s", p, &s.Sident[0]);
    if (st.Sbase || st.Svirtbase)
    {
        fprintf(fdmodule, ";\n");
        return;
    }

    fprintf(fdmodule, "\n");
    htod_indent(indent);
    fprintf(fdmodule, "{\n");
    uint memoff = ~0;
    uint bitfieldn = 0;
    char[10 + bitfieldn.sizeof * 3 + 1] bf = void;
    for (sl = st.Sfldlst; sl; sl = list_next(sl))
    {   Symbol *sf = list_symbol(sl);
        uint attribute = sf.Sflags & SFLpmask;
        char *pt;
        targ_ullong m;

        if (attribute && attribute != attr)
        {
            switch (attribute)
            {   case SFLprivate:        p = "private";          break;
                case SFLprotected:      p = "protected";        break;
                case SFLpublic:         p = "public";           break;
                default:
                    assert(0);
            }
            htod_indent(indent + 2);
            fprintf(fdmodule, "%s:\n", p);
            attr = attribute;
        }

        pt = htod_type_tostring(&buf, sf.Stype);
        switch (sf.Sclass)
        {
            case SCmember:
                memoff = sf.Smemoff;
                htod_indent(indent + 4);
                fprintf(fdmodule, "%s%s;\n", pt, &sf.Sident[0]);
                break;

            case SCfield:
                if (memoff != sf.Smemoff)
                {
                    sprintf(bf.ptr, "__bitfield%d", ++bitfieldn);
                    htod_indent(indent + 4);
                    fprintf(fdmodule, "%s%s;\n", pt, bf.ptr);
                    memoff = sf.Smemoff;
                }
                // Swidth, Sbit
                m = (cast(targ_ullong)1 << sf.Swidth) - 1;
                htod_indent(indent + 4);
                if (tyuns(sf.Stype.Tty))
                {
                    // Getter
                    fprintf(fdmodule, "%s%s() { return (%s >> %d) & 0x%llx; }\n",
                        pt, &sf.Sident[0],
                        bf.ptr,
                        sf.Sbit,
                        m);

                    // Setter
                    htod_indent(indent + 4);
                    fprintf(fdmodule, "
%s%s(%svalue) {
 %s = (%s & 0x%llx) | (value << %d);
 return value; }\n",
                        pt, &sf.Sident[0], pt,
                        bf.ptr, bf.ptr, ~(m << sf.Sbit), sf.Sbit);
                }
                else
                {   uint n = tysize(sf.Stype.Tty) * 8;
                    // Getter
                    fprintf(fdmodule, "%s%s() { return (%s << %d) >> %d; }\n",
                        htod_type_tostring(&buf, sf.Stype), &sf.Sident[0],
                        bf.ptr,
                        n - (sf.Sbit + sf.Swidth),
                        n - sf.Swidth);

                    // Setter
                    htod_indent(indent + 4);
                    fprintf(fdmodule, "
%s%s(%svalue) {
 %s = (%s & 0x%llx) | ((value & 0x%llx) << %d);
 return value; }\n",
                        pt, &sf.Sident[0], pt,
                        bf.ptr, bf.ptr, ~(m << sf.Sbit), m, sf.Sbit);
                }
                break;

            case SCstruct:
                indent += 4;
                htod_struct(cast(Classsym *)sf);
                indent -= 4;
                break;

            case SCenum:
                indent += 4;
                htod_enum(sf);
                indent -= 4;
                break;

            case SCtypedef:
                p = htod_type_tostring(&buf, s.Stype);
                if (strlen(p) == strlen(&s.Sident[0]) + 1 &&
                    memcmp(p, &s.Sident[0], strlen(&s.Sident[0])) == 0)
                    break;      // avoid alias X X;
                htod_indent(indent + 4);
                fprintf(fdmodule, "alias %s %s;\n", htod_type_tostring(&buf, s.Stype), &s.Sident[0]);
                break;

            case SCextern:
            case SCcomdef:
            case SCglobal:
            case SCstatic:
            case SCinline:
            case SCsinline:
            case SCeinline:
            case SCcomdat:
                break;

            default:
                break;
        }
    }
    htod_indent(indent);
    fprintf(fdmodule, "}\n");
}

void htod_enum(Symbol *s)
{   type *tbase;
    Outbuffer buf;

    //printf("htod_enum('%s')\n", &s.Sident[0]);
    tbase = s.Stype.Tnext;

    htod_indent(indent);
    if (s.Senum.SEflags & SENnotagname)
        fprintf(fdmodule, "enum");
    else
        fprintf(fdmodule, "enum %s", &s.Sident[0]);
    if (tybasic(tbase.Tty) != TYint)
    {
        fprintf(fdmodule, " : %s", htod_type_tostring(&buf, tbase));
    }
    if (s.Senum.SEflags & SENforward)
    {
        fprintf(fdmodule, ";\n");
        return;
    }
    fprintf(fdmodule, "\n");

    htod_indent(indent);
    fprintf(fdmodule, "{\n");

    targ_ullong lastvalue = 0;
    for (symlist_t sl = s.Senum.SEenumlist; sl; sl = list_next(sl))
    {   Symbol *sf = list_symbol(sl);
        targ_ullong value;

        symbol_debug(sf);
        value = el_tolongt(sf.Svalue);
        htod_indent(indent + 4);
        fprintf(fdmodule, "%s", &sf.Sident[0]);
        if (lastvalue != value)
        {
            buf.reset();
            fprintf(fdmodule, " = %s", htod_el_tostring(&buf, sf.Svalue));
        }
        fprintf(fdmodule, ",\n");
        lastvalue = value + 1;
    }

    htod_indent(indent);
    fprintf(fdmodule, "}\n");
}

void htod_decl(Symbol *s)
{
    if (s &&
        htod_output() &&
        anylines)
    {   Outbuffer buf;
        mangle_t m = type_mangle(s.Stype);
        tym_t ty = tybasic(s.Stype.Tty);

        if (m && m != dlinkage)
        {   const(char)* p;

            switch (m)
            {
                case mTYman_c:          p = "C";        break;
                case mTYman_cpp:        p = "C++";      return;
                case mTYman_pas:        p = "Pascal";   break;
                case mTYman_for:        p = "FORTRAN";  break;
                case mTYman_sys:        p = "Syscall";  break;
                case mTYman_std:        p = "Windows";  break;
                case mTYman_d:          p = "D";        break;
                default:
                    assert(0);
            }
            fprintf(fdmodule, "extern (%s):\n", p);
            dlinkage = m;
        }

        switch (s.Sclass)
        {
            case SCtypedef:
            {
                char *p;
                p = htod_type_tostring(&buf, s.Stype);
                if (strlen(p) == strlen(&s.Sident[0]) + 1 &&
                    memcmp(p, &s.Sident[0], strlen(&s.Sident[0])) == 0)
                    break;      // avoid alias X X;
                fprintf(fdmodule, "alias %s%s;\n", p, &s.Sident[0]);
                break;
            }
            case SCstruct:
                htod_struct(cast(Classsym *)s);
                break;

            case SCenum:
                htod_enum(s);
                break;

            case SCextern:
            case SCglobal:
            case SCconst:
            case SCcomdat:
            case SCinline:
            case SCsinline:
            case SCstatic:
                if (tyfunc(s.Stype.Tty))
                {
                    // Unsupported combinations
                    if (m == mTYman_c && ty != TYnfunc)
                        return;
                    if (m == mTYman_std && ty != TYnsfunc)
                        return;
                    if (m == mTYman_pas && ty != TYnpfunc)
                        return;

                    fprintf(fdmodule, "%s", htod_type_tostring(&buf, s.Stype.Tnext));
                    fprintf(fdmodule, " %s", &s.Sident[0]);
                    fprintf(fdmodule, "%s;\n", htod_param_tostring(&buf, s.Stype));
//symbol_print(s);
                }
                else
                {
                    if (s.Sclass == SCextern)
                        fprintf(fdmodule, "extern ");
                    if (s.Sclass == SCconst || s.Stype.Tty & mTYconst)
                        fprintf(fdmodule, "const ");
                    fprintf(fdmodule, "%s%s", htod_type_tostring(&buf, s.Stype), &s.Sident[0]);
                    if ((s.Sclass == SCconst || s.Stype.Tty & mTYconst) &&
                        s.Sflags & SFLvalue)
                    {
                        buf.reset();
                        fprintf(fdmodule, " = %s", htod_el_tostring(&buf, s.Svalue));
                    }
                    fprintf(fdmodule, ";\n");
                }
                break;

            default:
                fprintf(fdmodule, "symbol %s\n", &s.Sident[0]);
//symbol_print(s);
                break;
        }
    }
}

char *htod_type_tostring(Outbuffer *buf,type *t)
{
    tym_t ty;
    const(char)* s;
    type *tn;
    Outbuffer buf2;
    mangle_t mangle;

    //printf("htod_type_tostring()\n");
    //type_print(t);
    buf.reset();
    for (; t; t = t.Tnext)
    {
        type_debug(t);

        if (t.Ttypedef)
        {   if (t.Ttypedef.Sclass == SCenum &&
                t.Ttypedef.Senum.SEflags & SENnotagname)
            {
            }
            else if (!(config.htodFlags & HTODFtypedef))
            {
                buf.write(&t.Ttypedef.Sident[0]);
                buf.write(" ");
                return buf.toString();
            }
        }

        mangle = type_mangle(t);
        ty = t.Tty;

        ty = tybasic(ty);
        assert(ty < TYMAX);

        switch (ty)
        {   case TYarray:
                buf.write(htod_type_tostring(&buf2, t.Tnext));
                buf.write("[");
                if (t.Tflags & TFstatic)
                    buf.write("static ");
                if (t.Tflags & TFvla)
                    buf.write("*");
                else if (t.Tflags & TFsizeunknown)
                { }
                else
                {   char[uint.sizeof * 3 + 1] buffer = void;

                    sprintf(&buffer[0],"%u",cast(uint)t.Tdim);
                    buf.write(&buffer[0]);
                }
                buf.write("]");
                return buf.toString();

            case TYident:
                buf.write(t.Tident);
                break;

            case TYtemplate:
                buf.write(cast(char *)(cast(typetemp_t *)t).Tsym.Sident);
                buf.write("!(");
                htod_ptpl_tostring(buf, t.Tparamtypes);
                buf.write(")");
                break;

            case TYenum:
//              if (t.Ttag && t.Ttag.Sclass == SCenum &&
//                  t.Ttag.Senum.SEflags & SENnotagname)
                    break;
            case TYstruct:
                buf.write(t.Ttag ? prettyident(t.Ttag) : "{}");
                buf.writeByte(' ');
                return buf.toString();

            case TYmemptr:
                buf.writeByte(' ');
                buf.write(t.Ttag ? prettyident(t.Ttag) : "struct {}");
                buf.write("::*");
                if (tyfunc(t.Tnext.Tty) || tybasic(t.Tnext.Tty == TYarray))
                    break;
                else
                {
                    buf.prependBytes(htod_type_tostring(&buf2,t.Tnext));
                    goto Lret;
                }

            case TYnptr:
            case TYsptr:
            case TYcptr:
            case TYhptr:
            case TYfptr:
            case TYvptr:
            case TYimmutPtr:
            case TYsharePtr:
            case TYrestrictPtr:
            case TYfgPtr:
                if (tyfunc(t.Tnext.Tty))
                {
                    buf.write(htod_type_tostring(&buf2, t.Tnext.Tnext));
                    buf.write(" function");
                    buf.write(htod_param_tostring(&buf2, t.Tnext));
                    return buf.toString();
                }
                goto case TYref;

            case TYref:
                buf.write(htod_type_tostring(&buf2, t.Tnext));
                buf.write("*");
                return buf.toString();

            default:
                if (tyfunc(ty))
                {
                    size_t len;

                    len = buf.size();
                    buf.write(tystring[ty]);
                    if (len)
                        buf.bracket('(',')');
                    buf.write(htod_param_tostring(&buf2,t));
                    buf.prependBytes(htod_type_tostring(&buf2,t.Tnext));
                    goto Lret;
                }
                else
                {   const(char)* q;

                    q = htod_typestring(ty);
                    buf2.reset();
                    buf2.write(q);
                    if (isalpha(q[strlen(q) - 1]))
                        buf2.writeByte(' ');
                    buf.prependBytes(buf2.toString());
                }
                break;
        }
    }
Lret:
    return buf.toString();
}

/*********************************
 * Convert function parameter list to a string.
 * Caller must free returned string.
 */

char *htod_param_tostring(Outbuffer *buf,type *t)
{
    param_t *pm;
    __gshared const(char)* ellipsis = "...";

    type_debug(t);
    buf.reset();
    if (!tyfunc(t.Tty))
        goto L1;
    buf.writeByte('(');
    pm = t.Tparamtypes;
    if (!pm)
    {
        if (t.Tflags & TFfixed)
        { }
        else
            buf.write(ellipsis);
    }
    else
    {   Outbuffer pbuf;

        while (1)
        {   buf.write(htod_type_tostring(&pbuf,pm.Ptype));
            if (pm.Pident)
                buf.write(pm.Pident);
            pm = pm.Pnext;
            if (pm)
                buf.write(", ");
            else if (!(t.Tflags & TFfixed))
            {   buf.write(",...");
                break;
            }
            else
                break;
        }
    }
    buf.writeByte(')');
L1:
    return buf.toString();
}

/******************************
 * Convert argument list into a string.
 */

char *htod_arglist_tostring(Outbuffer *buf,list_t el)
{
    buf.reset();
    buf.writeByte('(');
    if (el)
    {   Outbuffer ebuf;

        while (1)
        {
            elem_debug(list_elem(el));
            buf.write(htod_type_tostring(&ebuf,list_elem(el).ET));
            el = list_next(el);
            if (!el)
                break;
            buf.writeByte(',');
        }
    }
    buf.writeByte(')');
    return buf.toString();
}

/*********************************
 * Convert function parameter list to a string.
 * Caller must free returned string.
 */

char *htod_ptpl_tostring(Outbuffer *buf, param_t *ptpl)
{
    //printf("htod_ptpl_tostring():\n");
    for (; ptpl; ptpl = ptpl.Pnext)
    {   Outbuffer pbuf;

        if (ptpl.Ptype)
            buf.write(htod_type_tostring(&pbuf, ptpl.Ptype));
        else if (ptpl.Pelem)
            buf.write(htod_el_tostring(&pbuf, ptpl.Pelem));
        else if (ptpl.Pident)
            buf.write(ptpl.Pident);
        if (ptpl.Pnext)
            buf.writeByte(',');
    }
    //printf("-htod_ptpl_tostring()\n");
    return buf.toString();
}

/**********************************
 * Convert elem to string.
 */

char *htod_el_tostring(Outbuffer *buf, elem *e)
{
    //printf("htod_el_tostring(): "); elem_print(e);

    switch (e.Eoper)
    {
        case OPvar:
            buf.write(&e.EV.Vsym.Sident[0]);
            break;

        case OPconst:
        {
            char[1 + targ_llong.sizeof * 3 + 1] buffer = void;
            const(char)* fmt = "%lld";
            switch (tybasic(e.ET.Tty))
            {
                case TYbool:
                    sprintf(&buffer[0], "%s", cast(const(char)*)(el_tolongt(e) ? "true" : "false"));
                    goto L1;
                case TYchar:
                case TYuchar:
                case TYchar16:
                case TYwchar_t:
                case TYushort:
                case TYuint:
                case TYdchar:
                case TYulong:           fmt = "%lluU";  break;
                case TYllong:           fmt = "%lldL";  break;
                case TYullong:          fmt = "%lluUL"; break;

                default:
                    break;
            }
            sprintf(&buffer[0], fmt, el_tolongt(e));
        L1:
            buf.write(&buffer[0]);
            break;
        }

        // BUG: should handle same cases as in newman.c
        default:
            break;
    }
    return buf.toString();
}

/**********************************
 * Get D type string corresponding to type.
 */

const(char)* htod_typestring(tym_t ty)
{   const(char)* p;
    ty = tybasic(ty);

    switch (ty)
    {
        case TYbool:            p = "bool";     break;
        case TYchar:            p = "char";     break;
        case TYschar:           p = "byte";     break;
        case TYuchar:           p = "ubyte";    break;
        case TYshort:           p = "short";    break;
        case TYchar16:
        case TYwchar_t:         p = "wchar";    break;
        case TYushort:          p = "ushort";   break;
        case TYint:             p = "int";      break;
        case TYuint:            p = "uint";     break;
        case TYlong:            p = "int";      break;
        case TYulong:           p = "uint";     break;
        case TYdchar:           p = "dchar";    break;
        case TYllong:           p = "long";     break;
        case TYullong:          p = "ulong";    break;
        case TYfloat:           p = "float";    break;
        case TYdouble:          p = "double";   break;

        case TYdouble_alias:    p = "double";   break;
        case TYldouble:         p = "real";     break;

        case TYifloat:          p = "ifloat";   break;
        case TYidouble:         p = "idouble";  break;
        case TYildouble:        p = "ireal";    break;
        case TYcfloat:          p = "cfloat";   break;
        case TYcdouble:         p = "cdouble";  break;
        case TYcldouble:        p = "creal";    break;

        default:
            p = tystring[ty];
            break;
    }

    return p;
}

}
else
{

import dmd.backend.cdef;
import dmd.backend.cc;

import parser;

extern (C++):

void htod_init(const(char)* name) { }

void htod_term() { }

bool htod_running()
{
    return false;
}

/* Stub them out
 */

void htod_decl(Symbol *s) { }

void htod_define(macro_t *m) { }

}
