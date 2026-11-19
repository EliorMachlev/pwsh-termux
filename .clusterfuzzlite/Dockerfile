# The base image ClusterFuzzLite provides for Python targets (Atheris and the
# build helpers are in it). It is the one image CI pulls that is not pinned by
# digest: the tag moves with ClusterFuzzLite's own releases.
FROM gcr.io/oss-fuzz-base/base-builder-python

COPY . $SRC/pwsh-termux
WORKDIR $SRC/pwsh-termux
COPY .clusterfuzzlite/build.sh $SRC/
