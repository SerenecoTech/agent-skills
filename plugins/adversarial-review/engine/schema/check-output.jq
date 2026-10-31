# Check a reviewer's out.json against findings.json, so a provider's output is held to the
# schema itself and not to a list of key names that can drift from it.
#
#   jq -c --slurpfile schema findings.json -f check-output.jq out.json
#
# Prints a JSON array of error strings; [] means the output is valid. Supports the keywords
# findings.json uses: type (one or a list), required, properties, additionalProperties: false,
# items and enum. A schema that starts using another keyword needs it added here.

def type_ok($want):
  type as $have
  | $want == $have or ($want == "integer" and $have == "number" and floor == .);

def errs($s; $path):
  . as $v
  | (if $s.type == null then []
     elif ([$s.type] | flatten | any(. as $t | $v | type_ok($t))) then []
     else ["\($path): expected \([$s.type] | flatten | join(" or ")), got \($v | type)"]
     end)
  + (if $s.enum == null or any($s.enum[]; . == $v) then []
     else ["\($path): \($v | tojson) is not one of \($s.enum | join(", "))"]
     end)
  + (if ($v | type) != "object" then []
     else
       [($s.required // [])[] | select(. as $k | $v | has($k) | not) | "\($path): missing \(.)"]
       + [($s.properties // {}) | to_entries[] | select(.key as $k | $v | has($k))
          | . as $p | ($v[$p.key] | errs($p.value; "\($path).\($p.key)"))[]]
       + (if $s.additionalProperties == false
          then [$v | keys[] | select(. as $k | $s.properties // {} | has($k) | not) | "\($path): unexpected \(.)"]
          else [] end)
     end)
  + (if ($v | type) != "array" or $s.items == null then []
     else [range(0; $v | length) as $i | ($v[$i] | errs($s.items; "\($path)[\($i)]"))[]]
     end);

errs($schema[0]; "$")
