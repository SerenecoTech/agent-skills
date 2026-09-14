# =============================================================================
# shell-segments.awk — split a shell command into command-position segments
# =============================================================================
# Quote- and heredoc-aware. Lets a guard ask "is this word the command?"
# instead of "does this word appear anywhere in the string?".
#
# Input : the full command on stdin. May span several lines.
# Output: depends on -v mode=
#
#   unquoted one line per segment, "L<list>S<stage>\t<text>", quote characters
#            removed and their contents kept. A quoted command word still runs,
#            so "sudo" rm reads as sudo here, while a quoted argument keeps its
#            text for filename checks.
#   orig     the same segments, original text. Use this in denial messages.
#   flat     the whole command on one line, quote characters and backslashes
#            removed and whitespace squeezed.
#
# Both segmented modes emit the same segments in the same order, so an index
# means the same thing in either.
#
# A new list (L) starts at ; & && || newline ( ) { } and at a command
# substitution boundary. A new stage (S) starts at |. Only stage 1 of a list
# reads a file; later stages are filtering what the earlier one printed.
#
# Heredoc bodies are data, never code, so they are dropped in every mode.

{ if (NR > 1) buf = buf "\n"; buf = buf $0 }

function oneline(s) { gsub(/\n/, " ", s); return s }

function emit(   lbl) {
    if (cur_o ~ /[^ \t\n]/) {
        lbl = "L" list "S" stage
        if (mode == "unquoted")  print lbl "\t" oneline(cur_u)
        else if (mode == "orig") print lbl "\t" oneline(cur_o)
    }
    cur_u = ""; cur_o = ""
}

function newlist(sep) { emit(); list++; stage = 1; flat = flat sep }
function newstage(sep) { emit(); stage++; flat = flat sep }

function add(u, o) { cur_u = cur_u u; cur_o = cur_o o; flat = flat u }

# Skip past the body of every heredoc opened on the line just ended.
function eat_heredocs(   d, e, line, t, z) {
    while (hd_count > 0) {
        d = hd_delim[1]
        while (i <= n) {
            e = index(substr(buf, i), "\n")
            if (e == 0) { line = substr(buf, i); i = n + 1 }
            else        { line = substr(buf, i, e - 1); i = i + e }
            t = line
            sub(/^[ \t]+/, "", t)
            sub(/[ \t]+$/, "", t)
            if (t == d) break
        }
        for (z = 1; z < hd_count; z++) hd_delim[z] = hd_delim[z + 1]
        hd_count--
    }
}

# Read the delimiter word of a heredoc starting at buf[i] ("<<" or "<<-").
# Returns the index just past the delimiter; records the delimiter.
function read_heredoc_delim(   j, q, k, delim) {
    j = i + 2
    if (substr(buf, j, 1) == "-") j++
    while (j <= n && (substr(buf, j, 1) == " " || substr(buf, j, 1) == "\t")) j++
    q = substr(buf, j, 1)
    if (q == "'" || q == "\"") {
        k = index(substr(buf, j + 1), q)
        if (k == 0) return i + 2
        delim = substr(buf, j + 1, k - 1)
        j = j + 1 + k
    } else {
        k = j
        while (k <= n && substr(buf, k, 1) ~ /[A-Za-z0-9_.-]/) k++
        delim = substr(buf, j, k - j)
        j = k
    }
    if (delim == "") return i + 2
    hd_count++
    hd_delim[hd_count] = delim
    return j
}

END {
    n = length(buf)
    list = 1
    stage = 1
    depth = 1
    st[1] = "C"          # C = code, Q = single quoted, D = double quoted
    hd_count = 0
    i = 1

    while (i <= n) {
        c = substr(buf, i, 1)

        # --- inside a single-quoted string: everything is data -------------
        if (st[depth] == "Q") {
            if (c == "'") { depth--; add("", c) }
            else          { add(c, c) }
            i++
            continue
        }

        # --- inside a double-quoted string ---------------------------------
        if (st[depth] == "D") {
            if (c == "\\") {
                add(substr(buf, i + 1, 1), substr(buf, i, 2))
                i += 2
                continue
            }
            if (c == "\"") { depth--; add("", c); i++; continue }
            if (c == "$" && substr(buf, i + 1, 1) == "(") {
                add("", "$(")
                newlist(" ")
                depth++; st[depth] = "C"
                i += 2
                continue
            }
            if (c == "`") {
                add("", "`")
                newlist(" ")
                depth++; st[depth] = "C"; sub_open[depth] = 1
                i++
                continue
            }
            add(c, c)
            i++
            continue
        }

        # --- code ----------------------------------------------------------
        if (c == "\\") {
            # An escaped character is still part of the word: \s\udo is sudo.
            d = substr(buf, i + 1, 1)
            if (d == "\n")                  { add("", "\\\n") }
            else if (d ~ /[;&|()`{}<> \t]/) { add(" ", "\\" d) }
            else                            { add(d, "\\" d) }
            i += 2
            continue
        }
        if (c == "'") { depth++; st[depth] = "Q"; add("", c); i++; continue }
        if (c == "\"") { depth++; st[depth] = "D"; add("", c); i++; continue }
        if (c == "$" && substr(buf, i + 1, 1) == "(") {
            add("", "$(")
            newlist(" ")
            depth++; st[depth] = "C"
            i += 2
            continue
        }
        if (c == "`") {
            add("", "`")
            newlist(" ")
            if (depth > 1 && st[depth] == "C" && sub_open[depth]) { sub_open[depth] = 0; depth-- }
            else { depth++; st[depth] = "C"; sub_open[depth] = 1 }
            i++
            continue
        }
        if (c == "<" && substr(buf, i + 1, 1) == "<" && substr(buf, i + 2, 1) != "<") {
            j = read_heredoc_delim()
            add(substr(buf, i, j - i), substr(buf, i, j - i))
            i = j
            continue
        }
        if (c == "\n") {
            newlist(" ")
            i++
            if (hd_count > 0) eat_heredocs()
            continue
        }
        if (c == ";") { newlist(";"); i++; continue }
        if (c == "&") {
            if (substr(buf, i + 1, 1) == "&") { newlist(" && "); i += 2 }
            else                              { newlist(" & "); i++ }
            continue
        }
        if (c == "|") {
            if (substr(buf, i + 1, 1) == "|") { newlist(" || "); i += 2 }
            else                              { newstage("|"); i++ }
            continue
        }
        if (c == "(" || c == "{" || c == "}") { newlist(c); i++; continue }
        if (c == ")") {
            newlist(c)
            if (depth > 1) depth--
            i++
            continue
        }
        add(c, c)
        i++
    }

    emit()

    if (mode == "flat") {
        gsub(/[ \t\n]+/, " ", flat)
        sub(/^ /, "", flat)
        print flat
    }
}
