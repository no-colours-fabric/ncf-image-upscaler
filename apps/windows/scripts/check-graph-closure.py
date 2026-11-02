"""Developer-only graph validation with onnx==1.16.0, not a user dependency."""

import argparse
import hashlib
import json
from pathlib import Path

import onnx

parser = argparse.ArgumentParser()
parser.add_argument("--model-root", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
assert onnx.__version__ == "1.16.0"


def tensors(graph):
    yield from graph.initializer
    for sparse in graph.sparse_initializer:
        yield sparse.values
        yield sparse.indices
    for node in graph.node:
        for attribute in node.attribute:
            if attribute.type == onnx.AttributeProto.TENSOR:
                yield attribute.t
            if attribute.type == onnx.AttributeProto.TENSORS:
                yield from attribute.tensors
            if attribute.type == onnx.AttributeProto.GRAPH:
                yield from tensors(attribute.g)
            if attribute.type == onnx.AttributeProto.GRAPHS:
                for child in attribute.graphs:
                    yield from tensors(child)


rows = []
app = Path(__file__).resolve().parents[1]
for spec in json.loads((app / "models.json").read_text(encoding="utf-8")):
    path = args.model_root / (spec["id"] + "-" + spec["sha256"] + ".onnx")
    with path.open("rb") as file:
        assert hashlib.file_digest(file, "sha256").hexdigest() == spec["sha256"]
    model = onnx.load(str(path), load_external_data=False)
    assert not model.functions and not model.training_info, "Unsupported graph containers; refuse"
    external = sum(
        t.data_location == onnx.TensorProto.EXTERNAL or bool(t.external_data)
        for t in tensors(model.graph)
    )
    assert external == 0, "External-data model is not described by this manifest; refuse it"
    onnx.checker.check_model(model)
    rows.append(
        dict(
            id=spec["id"],
            sha256=spec["sha256"],
            external_data=external,
            checker=onnx.__version__,
            graph_checked=True,
        )
    )
args.output.write_text(json.dumps(rows, indent=2), encoding="utf-8")
print(json.dumps(rows))
