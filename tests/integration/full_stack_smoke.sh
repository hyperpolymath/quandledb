#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0

set -euo pipefail

cd "$(dirname "$0")/../../"

echo "=== QuandleDB Full-Stack Smoke Test ==="

# Build the Julia server manifest if needed
echo "-> Instantiating Julia environment..."
julia --project=server -e 'using Pkg; Pkg.instantiate()'

# Start the Julia HTTP server on a random high port
PORT=18081
echo "-> Starting Julia server on port $PORT..."
julia --project=server server/serve.jl data/knots.db --port $PORT &
SERVER_PID=$!

# Wait for server to be ready
echo "-> Waiting for server to become responsive..."
MAX_ATTEMPTS=30
ATTEMPT=0
READY=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -s "http://127.0.0.1:$PORT/api/knots?limit=1" > /dev/null; then
        READY=1
        break
    fi
    sleep 1
    ATTEMPT=$((ATTEMPT + 1))
done

if [ $READY -eq 0 ]; then
    echo "ERROR: Server failed to start or respond in time."
    kill $SERVER_PID
    exit 1
fi

echo "-> Server is ready."

# Run the BEAM tests against the live server
echo "-> Running BEAM tests against live server..."
export QDB_LIVE_TEST_BASE_URL="http://127.0.0.1:$PORT"
export QDB_NIF_MODE="live"
export QDB_API_BASE_URL="http://127.0.0.1:$PORT"
cd beam
if mix test; then
    echo "-> BEAM live integration tests passed!"
    TEST_RESULT=0
else
    echo "ERROR: BEAM live integration tests failed."
    TEST_RESULT=1
fi
cd ..

# Cleanup
echo "-> Terminating Julia server (PID $SERVER_PID)..."
kill $SERVER_PID || true

echo "=== Smoke Test Complete (Exit Code: $TEST_RESULT) ==="
exit $TEST_RESULT
