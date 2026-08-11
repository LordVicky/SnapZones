#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ii_root="${VYNX_ZONES_II_ROOT:-${HOME}/.config/quickshell/ii}"
qml_imports=("-I" "${ii_root}" "-I" "/usr/lib64/qt6/qml")

if ! command -v node >/dev/null 2>&1; then
    echo "validate: node is required" >&2
    exit 1
fi

node --input-type=module -e 'import fs from "node:fs"; JSON.parse(fs.readFileSync(process.argv[1] + "/extension.json", "utf8"));' \
    -- "${repo_dir}" >/dev/null
echo "validate: extension.json parses"

node --test "${repo_dir}"/tests/*.test.mjs

# QML's .pragma library is valid to Qt but not to node --check. Remove only
# that directive in a temporary copy so the rest of each JS module receives a
# normal JavaScript syntax check without mutating the repository.
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
while IFS= read -r js_file; do
    relative="${js_file#"${repo_dir}/"}"
    target="${tmp_dir}/${relative}"
    mkdir -p "$(dirname "${target}")"
    sed '/^\.pragma library[[:space:]]*$/d' "${js_file}" > "${target}"
    node --check "${target}"
done < <(find "${repo_dir}/src" -type f -name '*.js' -print)
echo "validate: JavaScript syntax passes"

mapfile -t qml_files < <(find "${repo_dir}/src" -type f -name '*.qml' -print | sort)
if command -v qmllint-qt6 >/dev/null 2>&1; then
    # Run the parser-only pass first. The normal analysis below intentionally
    # tolerates unresolved qs.* runtime imports, but a syntax error must always
    # fail validation regardless of the warning policy in the host's qmllint
    # settings.
    qmllint-qt6 --silent "${qml_imports[@]}" "${qml_files[@]}"
    echo "validate: QML syntax passes"
    # The extension uses ii-vynx's runtime-only qs.* imports. Keep those
    # unresolved runtime types/unqualified style warnings as an explicit
    # environment allowlist, while promoting structural and safety-relevant
    # diagnostics to errors so new QML defects fail validation.
    strict_qmllint_options=(
        --ignore-settings
        --access-singleton-via-object error
        --alias-cycle error
        --assignment-in-condition error
        --comma error
        --component-children-count error
        --confusing-expression-statement error
        --confusing-minuses error
        --confusing-pluses error
        --context-properties error
        --deprecated error
        --duplicate-enum-entries error
        --duplicate-import error
        --duplicate-inline-component error
        --duplicate-property-binding error
        --duplicated-name error
        --enum-entry-matches-enum error
        --eval error
        --inheritance-cycle error
        --invalid-lint-directive error
        --literal-constructor error
        --missing-enum-entry error
        --non-list-property error
        --non-root-enum error
        --property-override error
        --read-only-property error
        --redundant-optional-chaining error
        --required error
        --signal-handler-parameters warning
        --stale-property-read error
        --top-level-component error
        --translation-function-mismatch error
        --unintentional-empty-block error
        --unreachable-code error
        --unresolved-alias error
        --var-used-before-declaration error
        --with error
    )
    qmllint-qt6 "${qml_imports[@]}" "${strict_qmllint_options[@]}" "${qml_files[@]}"
    echo "validate: QML lint passes (ii-vynx runtime imports remain an explicit warning allowlist)"
else
    echo "validate: qmllint-qt6 not installed; skipped QML lint" >&2
fi

if command -v qmlformat-qt6 >/dev/null 2>&1; then
    if [[ "${VYNX_ZONES_FORMAT_CHECK:-0}" == "1" ]]; then
        # qmlformat-qt6 has no --check on the target environment. Format into
        # a temporary file and compare, preserving the working tree.
        for qml_file in "${qml_files[@]}"; do
            formatted="${tmp_dir}/$(basename "${qml_file}").formatted"
            qmlformat-qt6 "${qml_file}" > "${formatted}"
            if ! cmp -s "${qml_file}" "${formatted}"; then
                echo "validate: formatting differs: ${qml_file}" >&2
                exit 1
            fi
        done
        echo "validate: QML formatting passes"
    else
        for qml_file in "${qml_files[@]}"; do
            qmlformat-qt6 "${qml_file}" > /dev/null
        done
        echo "validate: QML formatter parses files (set VYNX_ZONES_FORMAT_CHECK=1 for a strict comparison)"
    fi
else
    echo "validate: qmlformat-qt6 not installed; skipped QML formatting" >&2
fi

echo "validate: all checks passed"
