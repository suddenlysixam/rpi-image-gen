#!/bin/bash

# rpi-image-gen metadata parsing test suite
# Usage: just run it

IGTOP=$(readlink -f "$(dirname "$0")/../../")
LAYERS="${IGTOP}/test/layer"

PATH="$IGTOP/bin:$PATH"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Result tracking
declare -a FAILED_TEST_NAMES=()

print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================${NC}"
}

print_test() {
    echo -e "${YELLOW}Testing: $1${NC}"
}

print_pass() {
    echo -e "${GREEN}✓ PASS: $1${NC}"
    ((PASSED_TESTS++))
}

print_fail() {
    echo -e "${RED}✗ FAIL: $1${NC}"
    echo -e "${RED}  Error: $2${NC}"
    ((FAILED_TESTS++))
    FAILED_TEST_NAMES+=("$1")
}

run_test() {
    local test_name="$1"
    local command="$2"
    local expected_exit_code="$3"
    local description="$4"

    ((TOTAL_TESTS++))
    print_test "$test_name"

    # Run the command and capture both stdout and stderr
    local output
    output=$(eval "$command" 2>&1)
    local actual_exit_code=$?

    if [ "$actual_exit_code" -eq "$expected_exit_code" ]; then
        print_pass "$description"
    else
        print_fail "$description" "Expected exit code $expected_exit_code, got $actual_exit_code. Output: $output"
    fi

    echo ""
}

print_summary() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}TEST SUMMARY${NC}"
    echo -e "${BLUE}================================${NC}"
    echo -e "Total tests: $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"

    if [ ${#FAILED_TEST_NAMES[@]} -gt 0 ]; then
        echo -e "\n${RED}Failed tests:${NC}"
        for test in "${FAILED_TEST_NAMES[@]}"; do
            echo -e "${RED}  - $test${NC}"
        done
    fi

    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}Some tests failed. Please check the output above.${NC}"
        exit 1
    fi
}

cleanup_env() {
    unset $(env | grep '^IGconf_' | cut -d= -f1)
    unset NONEXISTENT_VAR
}

setup_test_env() {
    export IGconf_basic_hostname="test-host"
    export IGconf_types_name="test-app"
    export IGconf_types_timeout="60"
    export IGconf_types_debug="true"
    export IGconf_types_environment="development"
    export IGconf_types_email="test@example.com"
    export IGconf_valfail_port="99999"
    export IGconf_valfail_email="not-an-email"
    export IGconf_valfail_required=""
}


# Valid basic metadata
print_header "VALID METADATA TESTS"

run_test "valid-basic-parse" \
    "ig metadata --parse ${LAYERS}/valid-basic.yaml" \
    0 \
    "Valid basic metadata should parse successfully"

run_test "valid-basic-validate" \
    "ig metadata --validate ${LAYERS}/valid-basic.yaml" \
    0 \
    "Valid basic metadata should parse successfully"

run_test "valid-string-or-empty" \
    "ig metadata --validate ${LAYERS}/string-or-empty.yaml" \
    0 \
    "Empty string is valid when using string-or-empty validation rule"

run_test "valid-basic-describe" \
    "ig metadata --describe ${LAYERS}/valid-basic.yaml" \
    0 \
    "Valid basic metadata should describe successfully"


# Valid all-types metadata
setup_test_env
run_test "valid-all-types-parse" \
    "ig metadata --parse ${LAYERS}/valid-all-types.yaml" \
    0 \
    "Valid all-types metadata should parse successfully"

run_test "valid-all-types-validate" \
    "ig metadata --validate ${LAYERS}/valid-all-types.yaml" \
    0 \
    "Valid all-types metadata should validate successfully"

run_test "valid-all-types-parse" \
    "ig metadata --parse ${LAYERS}/valid-all-types.yaml" \
    0 \
    "Valid all-types metadata should parse and set variables successfully"


# Valid requirements-only metadata
run_test "valid-requirements-only-parse" \
    "ig metadata --parse ${LAYERS}/valid-requirements-only.yaml" \
    0 \
    "Valid requirements-only metadata should parse successfully (no output expected)"

run_test "valid-requirements-only-validate" \
    "ig metadata --validate ${LAYERS}/valid-requirements-only.yaml" \
    0 \
    "Valid requirements-only metadata should validate successfully"


# Set policies
cleanup_env
run_test "set-policies-parse" \
    "ig metadata --parse ${LAYERS}/set-policies.yaml" \
    0 \
    "Set policies should work correctly"


print_header "INVALID METADATA TESTS"


# Invalid - no prefix
cleanup_env
run_test "invalid-no-prefix-parse" \
    "ig metadata --parse ${LAYERS}/invalid-no-prefix.yaml" \
    1 \
    "Metadata with variables but no prefix should fail to parse"

run_test "invalid-no-prefix-validate" \
    "ig metadata --validate ${LAYERS}/invalid-no-prefix.yaml" \
    1 \
    "Metadata with variables but no prefix should fail to validate"


# Invalid - malformed syntax
run_test "invalid-malformed-parse" \
    "ig metadata --parse ${LAYERS}/invalid-malformed.yaml" \
    1 \
    "Malformed metadata should fail to parse"

run_test "invalid-malformed-validate" \
    "ig metadata --validate ${LAYERS}/invalid-malformed.yaml" \
    1 \
    "Malformed metadata should fail to validate"


# Invalid - unsupported fields
run_test "invalid-unsupported-parse" \
    "ig metadata --parse ${LAYERS}/invalid-unsupported-fields.yaml" \
    1 \
    "Metadata with unsupported fields should fail to parse"

run_test "invalid-unsupported-validate" \
    "ig metadata --validate ${LAYERS}/invalid-unsupported-fields.yaml" \
    1 \
    "Metadata with unsupported fields should fail to validate"


# Invalid - YAML syntax
run_test "invalid-yaml-syntax-layer-validate" \
    "ig layer --validate ${LAYERS}/invalid-yaml-syntax.yaml" \
    1 \
    "Invalid YAML syntax should fail layer validation"


# Invalid - bad validation type
run_test "invalid-validation-type" \
    "ig metadata --validate ${LAYERS}/invalid-validation-type.yaml" \
    1 \
    "Invalid variable validation type should fail validation"


# Validation failures
cleanup_env
setup_test_env
run_test "validation-failures-parse" \
    "ig metadata --parse ${LAYERS}/validation-failures.yaml" \
    1 \
    "Metadata with validation failures should fail to parse"

run_test "validation-failures-validate" \
    "ig metadata --validate ${LAYERS}/validation-failures.yaml" \
    1 \
    "Metadata with validation failures should fail to validate"


print_header "LAYER FUNCTIONALITY TESTS"


# Layer with dependencies
setup_test_env

run_test "meta-validate-rejects-invalid-dependency-declaration" \
    "ig metadata --validate ${LAYERS}/invalid-layer-dep-fmt.yaml" \
    1 \
    "Meta validate should reject invalid declaration of dependencies"

run_test "meta-parse-rejects-invalid-dependency-declaration" \
    "ig metadata --parse ${LAYERS}/invalid-layer-dep-fmt.yaml" \
    1 \
    "Meta parse should perform validation of dependency declaration"

run_test "layer-with-deps-info" \
    "ig layer --path ${LAYERS} --describe test-with-deps" \
    0 \
    "Layer with dependencies should show info successfully"

run_test "layer-with-deps-validate" \
    "ig layer --path ${LAYERS} --validate test-with-deps" \
    0 \
    "Layer with dependencies should validate successfully"


# Layer with missing dependencies
run_test "layer-missing-dep-validate" \
    "ig layer --path ${LAYERS} --validate test-missing-dep" \
    1 \
    "Layer with missing dependencies should fail validation"

run_test "layer-missing-dep-check" \
    "ig layer --path ${LAYERS} --check test-missing-dep" \
    1 \
    "Layer dependency check should fail for missing dependencies"


# Circular dependencies
run_test "layer-circular-deps-check" \
    "ig layer --path ${LAYERS} --check test-circular-a" \
    1 \
    "Circular dependency check should fail"

run_test "layer-build-order-circular" \
    "ig layer --path ${LAYERS} --build-order test-circular-a" \
    1 \
    "Build order should fail for circular dependencies"


# Duplicate layer name detection uses a temp dir to avoid side effects
tmp_dup_dir=$(mktemp -d)
cp "${LAYERS}/valid-basic.yaml" "$tmp_dup_dir/layer1.yaml"
cp "${LAYERS}/valid-basic.yaml" "$tmp_dup_dir/layer2.yaml"

run_test "layer-duplicate-name-detection" \
    "ig layer --path $tmp_dup_dir --list >/dev/null 2>&1" \
    1 \
    "Duplicate layer names should cause discovery to fail"

# Clean up temporary directory
rm -rf "$tmp_dup_dir"


print_header "OTHER TESTS"


# Help commands
run_test "meta-help-validation" \
    "ig metadata --help-validation" \
    0 \
    "Help validation should work"

run_test "meta-gen" \
    "ig metadata --gen" \
    0 \
    "Metadata generation should work"


# Layer build order (valid case)
run_test "layer-build-order-valid" \
    "ig layer --path ${LAYERS} --build-order test-with-deps" \
    0 \
    "Build order should work for valid dependencies"


# Layer management discovery
run_test "layer-discovery" \
    "ig layer --path ${LAYERS} --describe test-basic" \
    0 \
    "Layer discovery should find test layers"


print_header "AUTO-SET AND APPLY-ENV TESTS"


# Metadata parse with auto-set from policy
cleanup_env
unset IGconf_net_interface
# Temporarily change Set policy to y for this test
sed -i 's/X-Env-Var-INTERFACE-Set: n/X-Env-Var-INTERFACE-Set: y/' ${LAYERS}/network-x-env.yaml
run_test "meta-parse-auto-set" \
    "ig metadata --parse ${LAYERS}/network-x-env.yaml" \
    0 \
    "Meta parse should auto-set variables with Set: y policy"
# Restore original setting
sed -i 's/X-Env-Var-INTERFACE-Set: y/X-Env-Var-INTERFACE-Set: n/' ${LAYERS}/network-x-env.yaml


# Layer apply-env with valid metadata
cleanup_env
run_test "layer-apply-env-valid" \
    "ig layer --path ${LAYERS} --apply-env test-set-policies" \
    0 \
    "Layer apply-env should work with valid metadata"


# Layer apply-env with invalid metadata
run_test "layer-apply-env-invalid" \
    "ig layer --path ${LAYERS} --apply-env test-unsupported" \
    1 \
    "Layer apply-env should fail with invalid metadata"


# Verify meta parse auto-sets required variables with Set: y
cleanup_env
unset IGconf_net_interface
IGconf_net_interface_before=$(env | grep IGconf_net_interface || echo "UNSET")
# Temporarily change Set policy to y for this test
sed -i 's/X-Env-Var-INTERFACE-Set: n/X-Env-Var-INTERFACE-Set: y/' ${LAYERS}/network-x-env.yaml
run_test "meta-parse-sets-required-vars" \
    "test \"\$IGconf_net_interface_before\" = \"UNSET\" && ig metadata --parse ${LAYERS}/network-x-env.yaml | grep 'IGconf_net_interface=eth0'" \
    0 \
    "Meta parse should set required variables from defaults when Set: y"
# Restore original setting
sed -i 's/X-Env-Var-INTERFACE-Set: y/X-Env-Var-INTERFACE-Set: n/' ${LAYERS}/network-x-env.yaml



# Test layer apply-env sets variables instead of skipping them
cleanup_env
unset IGconf_net_interface IGconf_net_ip IGconf_net_dns
# Temporarily change Set policy to y for this test
sed -i 's/X-Env-Var-INTERFACE-Set: n/X-Env-Var-INTERFACE-Set: y/' ${LAYERS}/network-x-env.yaml
run_test "layer-apply-env-sets-vars" \
    "ig layer --path ${LAYERS} --apply-env network-setup | grep -E '\\[SET\\].*IGconf_net_interface=eth0'" \
    0 \
    "Layer apply-env should SET variables, not skip them when they are unset"
# Restore original setting
sed -i 's/X-Env-Var-INTERFACE-Set: y/X-Env-Var-INTERFACE-Set: n/' ${LAYERS}/network-x-env.yaml


# Test metadata parse with required+auto-set variables works
cleanup_env
unset IGconf_net_interface IGconf_net_ip IGconf_net_dns
# Temporarily change Set policy to y for this test
sed -i 's/X-Env-Var-INTERFACE-Set: n/X-Env-Var-INTERFACE-Set: y/' ${LAYERS}/network-x-env.yaml
run_test "meta-parse-required-auto-set-regression" \
    "ig metadata --parse ${LAYERS}/network-x-env.yaml | grep 'IGconf_net_interface=eth0'" \
    0 \
    "Meta parse should work with required variables that have Set: y (regression test)"
# Restore original setting
sed -i 's/X-Env-Var-INTERFACE-Set: y/X-Env-Var-INTERFACE-Set: n/' ${LAYERS}/network-x-env.yaml


# Test both meta parse and layer apply-env work
cleanup_env
unset IGconf_net_interface IGconf_net_ip IGconf_net_dns
# Temporarily change Set policy to y for this test
sed -i 's/X-Env-Var-INTERFACE-Set: n/X-Env-Var-INTERFACE-Set: y/' ${LAYERS}/network-x-env.yaml
run_test "meta-parse-layer-apply-env-consistency" \
    "ig metadata --parse ${LAYERS}/network-x-env.yaml >/dev/null && ig layer --path ${LAYERS} --apply-env network-setup | grep -E '\\[SET\\].*IGconf_net_interface=eth0'" \
    0 \
    "Both meta parse and layer apply-env should work consistently with required+auto-set variables"
# Restore original setting
sed -i 's/X-Env-Var-INTERFACE-Set: y/X-Env-Var-INTERFACE-Set: n/' ${LAYERS}/network-x-env.yaml


# Test layer apply-env fails when required variable has Set: n and is not provided
cleanup_env
unset IGconf_net_interface IGconf_net_ip IGconf_net_dns
run_test "layer-apply-env-fails-required-no-set" \
    "ig layer --path ${LAYERS} --apply-env network-setup" \
    1 \
    "Layer apply-env should fail when required variables have Set: n and are not provided in environment"


# Test layer apply-env succeeds when required variable has Set: n but is provided
cleanup_env
unset IGconf_net_interface IGconf_net_ip IGconf_net_dns
export IGconf_net_interface=wlan0
run_test "layer-apply-env-succeeds-required-manually-set" \
    "ig layer --path ${LAYERS} --apply-env network-setup | grep -E '\\[SKIP\\].*IGconf_net_interface.*already set'" \
    0 \
    "Layer apply-env should succeed when required variables have Set: n but are manually provided"


# Test metadata parse fails when required variable has Set: n and is not provided
cleanup_env
unset IGconf_net_interface IGconf_net_ip IGconf_net_dns
run_test "meta-parse-fails-required-no-set" \
    "ig metadata --parse ${LAYERS}/network-x-env.yaml" \
    1 \
    "Meta parse should fail when required variables have Set: n and are not provided in environment"


# Test metadata parse succeeds when required variable has Set: n but is manually provided
cleanup_env
unset IGconf_net_interface IGconf_net_ip IGconf_net_dns
export IGconf_net_interface=wlan0
run_test "meta-parse-succeeds-required-manually-set" \
    "ig metadata --parse ${LAYERS}/network-x-env.yaml | grep 'IGconf_net_interface=wlan0'" \
    0 \
    "Meta parse should succeed when required variables have Set: n but are manually provided"


# Test lazy policy last-wins
cleanup_env
unset IGconf_lazy_path
run_test "lazy-last-wins" \
    "ig layer --path ${LAYERS} --apply-env test-lazy-second | grep -E '\[LAZY\].*IGconf_lazy_path=/usr/second'" \
    0 \
    "Lazy policy should apply last-wins value from test-lazy-second"

# Test force policy overrides existing value
cleanup_env
export IGconf_force_color=red
run_test "force-overwrite" \
    "ig layer --path ${LAYERS} --apply-env test-force-overwrite | grep -E '\[FORCE\].*IGconf_force_color=blue'" \
    0 \
    "Force policy should overwrite pre-existing env value"
cleanup_env

# Test placeholder substitution
cleanup_env
unset IGconf_placeholder_path
expected_dir="${LAYERS}"
run_test "placeholder-directory" \
   "ig metadata --parse ${LAYERS}/placeholder-test.yaml | grep \"IGconf_placeholder_path=${expected_dir}\"" \
   0 \
   "Placeholder ${DIRECTORY} should resolve to metadata directory"

# Provider capability tests
cleanup_env
run_test "provider-resolution" \
    "ig layer --path ${LAYERS} --check test-provider-base test-provider-consumer" \
    0 \
    "Provider check should pass if provider in dependency chain"

cleanup_env
run_test "provider-missing" \
    "ig layer --path ${LAYERS} --check test-provider-consumer-missing" \
    1 \
    "Check should fail when provider capability not available"

cleanup_env
# Provider conflict test - uses temporary files to avoid interfering with other tests
CONFLICT_DIR=$(mktemp -d)
cat > ${CONFLICT_DIR}/provider-conflict1.yaml << 'EOF'
# METABEGIN
# X-Env-Layer-Name: test-provider-conflict1
# X-Env-Layer-Version: 1.0.0
# X-Env-Layer-Provides: database
# X-Env-Layer-Category: test
# METAEND
EOF
cat > ${CONFLICT_DIR}/provider-conflict2.yaml << 'EOF'
# METABEGIN
# X-Env-Layer-Name: test-provider-conflict2
# X-Env-Layer-Version: 1.0.0
# X-Env-Layer-Provides: database
# X-Env-Layer-Category: test
# METAEND
EOF
run_test "provider-conflict" \
    "{ ig layer --path ${CONFLICT_DIR} --check test-provider-conflict1 test-provider-conflict2; RESULT=\$?; rm -rf ${CONFLICT_DIR}; exit \$RESULT; }" \
    1 \
    "Check should fail when multiple layers provide the same capability"

cleanup_env


# Test --write-out functionality
cleanup_env
unset IGconf_basic_hostname IGconf_basic_port
WRITE_TEST_FILE="/tmp/test-writeout-$$.env"
run_test "meta-parse-write-out" \
    "ig metadata --parse ${LAYERS}/valid-basic.yaml --write-out ${WRITE_TEST_FILE} >/dev/null && grep -q 'IGconf_basic_hostname=\"localhost\"' ${WRITE_TEST_FILE} && grep -q 'IGconf_basic_port=\"8080\"' ${WRITE_TEST_FILE}" \
    0 \
    "Meta parse --write-out should write variables to file"
rm -f ${WRITE_TEST_FILE}

cleanup_env  
unset IGconf_basic_hostname IGconf_basic_port
WRITE_TEST_FILE="/tmp/test-layer-writeout-$$.env"
run_test "layer-apply-env-write-out" \
    "ig layer --path ${LAYERS} --apply-env test-basic --write-out ${WRITE_TEST_FILE} >/dev/null && grep -q 'IGconf_basic_hostname=\"localhost\"' ${WRITE_TEST_FILE} && grep -q 'IGconf_basic_port=\"8080\"' ${WRITE_TEST_FILE}" \
    0 \
    "Layer apply-env --write-out should write changed variables to file"
rm -f ${WRITE_TEST_FILE}

cleanup_env
unset IGconf_basic_hostname IGconf_basic_port  
export IGconf_basic_hostname=already-set
WRITE_TEST_FILE="/tmp/test-writeout-partial-$$.env"
run_test "layer-apply-env-write-out-partial" \
    "ig layer --path ${LAYERS} --apply-env test-basic --write-out ${WRITE_TEST_FILE} >/dev/null && ! grep -q 'IGconf_basic_hostname' ${WRITE_TEST_FILE} && grep -q 'IGconf_basic_port=\"8080\"' ${WRITE_TEST_FILE}" \
    0 \
    "Layer apply-env --write-out should only write changed variables, not already-set ones"
rm -f ${WRITE_TEST_FILE}

cleanup_env
unset IGconf_basic_hostname IGconf_basic_port IGconf_types_name IGconf_types_timeout
WRITE_TEST_FILE="/tmp/test-multi-layer-writeout-$$.env"
run_test "layer-apply-env-write-out-multi-layer" \
    "ig layer --path ${LAYERS} --apply-env test-basic test-all-types --write-out ${WRITE_TEST_FILE} >/dev/null && grep -q 'IGconf_basic_hostname=\"localhost\"' ${WRITE_TEST_FILE} && grep -q 'IGconf_basic_port=\"8080\"' ${WRITE_TEST_FILE} && grep -q 'IGconf_types_name=\"myapp\"' ${WRITE_TEST_FILE} && grep -q 'IGconf_types_timeout=\"30\"' ${WRITE_TEST_FILE}" \
    0 \
    "Layer apply-env --write-out should write variables from ALL layers, not just the last one"
rm -f ${WRITE_TEST_FILE}

cleanup_env  
unset IGconf_basic_hostname IGconf_basic_port IGconf_deps_feature
WRITE_TEST_FILE="/tmp/test-deps-writeout-$$.env"
run_test "layer-apply-env-write-out-with-dependencies" \
    "ig layer --path ${LAYERS} --apply-env test-with-deps --write-out ${WRITE_TEST_FILE} >/dev/null && grep -q 'IGconf_basic_hostname=\"localhost\"' ${WRITE_TEST_FILE} && grep -q 'IGconf_basic_port=\"8080\"' ${WRITE_TEST_FILE} && grep -q 'IGconf_deps_feature=\"enabled\"' ${WRITE_TEST_FILE}" \
    0 \
    "Layer apply-env --write-out should write variables from dependencies AND target layer"
rm -f ${WRITE_TEST_FILE}

run_test "bulk-lint-all-yaml" '
    # 1) collect every *.yaml / *.yml
    files=($(find "${IGTOP}/layer" "${IGTOP}/device" "${IGTOP}/image" "${IGTOP}/examples" \
                 -type f \( -name "*.yaml" -o -name "*.yml" \)))
    total=${#files[@]}

    pass=0  fail=0  failed=()

    # 2) lint each file
    for f in "${files[@]}"; do
        filename=$(basename "$f")

        # Look for corresponding env file
        env_file="${IGTOP}/test/layer/env/dist/${filename}.env"

        # Run lint in a subshell with environment variables loaded
        if [[ -f "$env_file" ]]; then
            echo "Loading environment from: $env_file"
            if ( set -a; . "$env_file" && ig metadata --lint "$f" >/dev/null 2>&1 ); then
                ((pass++))
            else
                ((fail++))
                failed+=("$f")
            fi
        else
            # No env file, run normally
            if ig metadata --lint "$f" >/dev/null 2>&1; then
                ((pass++))
            else
                ((fail++))
                failed+=("$f")
            fi
        fi
    done

    # 3) show a short summary + any failures
    echo "Total: $total  OK: $pass  FAIL: $fail"
    if (( fail > 0 )); then
        printf "Failed files:\n%s\n" "${failed[@]}"
    fi

    # 4) success when every YAML passed
    [[ $pass -eq $total ]]
' 0 "All layer files under layer/, device/, image/, examples/ must lint successfully"

# Test variable dependency ordering using three-layer dependency chain and shell sourcing
# This robust test catches ordering bugs by using shell strict mode to detect undefined variables
cleanup_env
run_test "variable-dependency-order-robust" \
    'WRITE_OUT_FILE=$(mktemp) && 
     ig layer --path '"${LAYERS}"' --apply-env test-dependency-top --write-out "$WRITE_OUT_FILE" >/dev/null 2>&1 &&
     env -i bash -c '\''
       set -aeu  # Strict mode: -a export all, -e exit on error, -u error on undefined vars
       source "$1"
       # Verify variables resolved correctly (force policy should override lazy)
       [[ "$IGconf_dep_base" == "/test/base/path" ]] &&
       [[ "$IGconf_dep_component" == "enhanced-core" ]] &&  # Force override
       [[ "$IGconf_dep_service" == "enhanced-core-service" ]] &&  # Uses force value  
       [[ "$IGconf_dep_configpath" == "/test/base/path/config" ]] &&
       [[ "$IGconf_dep_finalpath" == "/test/base/path/enhanced-core-service/final" ]] &&
       [[ "$IGconf_dep_result" == "/test/base/path/config/enhanced-core/result" ]]
     '\'' _ "$WRITE_OUT_FILE" &&
     rm -f "$WRITE_OUT_FILE"' \
    0 \
    "Variables should be in correct dependency order and shell-sourceable with strict error checking"


print_header "ENVIRONMENT VARIABLE DEPENDENCY TESTS"

# Test environment variable dependency evaluation with proper environment
cleanup_env
export ARCH=arm64
export DISTRO=debian
run_test "env-var-deps-with-env" \
    "ig layer --path ${LAYERS} --check test-env-var-deps" \
    0 \
    "Environment variable dependencies should resolve when variables are set"

# Test environment variable dependency evaluation without environment variables
cleanup_env
unset ARCH DISTRO
run_test "env-var-deps-missing-env" \
    "ig layer --path ${LAYERS} --check test-env-var-deps" \
    1 \
    "Environment variable dependencies should fail when variables are missing"

# Test build order with environment variable dependencies
cleanup_env
export ARCH=arm64
export DISTRO=debian
run_test "env-var-deps-build-order" \
    "ig layer --path ${LAYERS} --build-order test-env-var-deps | grep -E 'test-basic|arm64-toolchain|debian-packages'" \
    0 \
    "Build order should include resolved environment variable dependencies"

# Test that static dependencies still work
cleanup_env
run_test "static-deps-still-work" \
    "ig layer --path ${LAYERS} --check test-basic" \
    0 \
    "Static dependencies should continue to work without environment variables"

# Test mixed static and environment variable dependencies
cleanup_env
export ARCH=arm64
export DISTRO=debian
run_test "mixed-deps-static-and-env" \
    "ig layer --path ${LAYERS} --check test-env-var-deps" \
    0 \
    "Mixed static and environment variable dependencies should work together"

# Test environment variable dependency validation
cleanup_env
export ARCH=arm64
export DISTRO=debian
run_test "env-var-deps-validate" \
    "ig layer --path ${LAYERS} --validate test-env-var-deps" \
    0 \
    "Environment variable dependencies should validate successfully"

# Test environment variable dependency apply-env
cleanup_env
export ARCH=arm64
export DISTRO=debian
run_test "env-var-deps-apply-env" \
    "ig layer --path ${LAYERS} --apply-env test-env-var-deps | grep -E '\\[SET\\].*IGconf_envtest_feature'" \
    0 \
    "Environment variable dependencies should work with apply-env"


print_summary
