# SPDX-License-Identifier: MPL-2.0
# QuandleDB KRL fragment verification image. This does not deploy the database.
# Build and execute the same dependency-free boundary checks used by CI:
#   podman build -t quandledb-krl-check .
#   podman run --rm quandledb-krl-check
FROM docker.io/library/julia:1.12.6@sha256:3688355d393347055ab3fe866dbb4231e5840ab9808382618996958f6f4a2489
WORKDIR /workspace
COPY server/krl/ server/krl/
COPY server/Diagnostics.jl server/Diagnostics.jl
RUN julia --startup-file=no server/krl/test/seam_test.jl \
 && julia --startup-file=no server/krl/test/resolution_boundary_test.jl
USER 65534:65534
CMD ["julia", "--startup-file=no", "server/krl/test/resolution_boundary_test.jl"]
