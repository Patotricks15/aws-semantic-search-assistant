"""Generates docs/architecture.drawio for the Serverless Semantic Search Assistant
project using drawpyo.

Run with: python3 scripts/generate_diagram.py
"""
import os

import drawpyo

OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")

AWS4_BASE = (
    "sketch=0;outlineConnect=0;fontColor=#232F3E;gradientColor=none;strokeColor=none;"
    "dashed=0;verticalLabelPosition=bottom;verticalAlign=top;align=center;html=1;"
    "fontSize=11;fontStyle=0;aspect=fixed;pointerEvents=1;"
)


def aws_style(icon_name, fill_color):
    return f"{AWS4_BASE}fillColor={fill_color};shape=mxgraph.aws4.resourceIcon;resIcon=mxgraph.aws4.{icon_name};"


def add_node(page, name, x, y, icon_name, fill_color, width=64, height=64):
    node = drawpyo.diagram.Object(page=page, value=name)
    node.position = (x, y)
    node.geometry.width = width
    node.geometry.height = height
    node.apply_style_string(aws_style(icon_name, fill_color))
    return node


def add_plain_node(page, name, x, y, width=90, height=64):
    node = drawpyo.diagram.Object(page=page, value=name)
    node.position = (x, y)
    node.geometry.width = width
    node.geometry.height = height
    node.apply_style_string(
        "rounded=0;whiteSpace=wrap;html=1;fillColor=#FFFFFF;strokeColor=#232F3E;"
        "fontSize=10;fontColor=#232F3E;align=center;verticalAlign=middle;"
    )
    return node


def add_group(page, name, x, y, width, height):
    group = drawpyo.diagram.Object(page=page, value=name)
    group.position = (x, y)
    group.geometry.width = width
    group.geometry.height = height
    group.apply_style_string(
        "rounded=0;whiteSpace=wrap;html=1;dashed=1;dashPattern=8 4;fillColor=none;"
        "strokeColor=#01A88D;verticalAlign=top;align=center;fontColor=#01A88D;fontSize=11;"
    )
    return group


def add_edge(page, source, target, label=None, bidirectional=False):
    edge = drawpyo.diagram.Edge(page=page, source=source, target=target, label=label)
    edge.waypoints = "orthogonal"
    edge.endArrow = "block"
    edge.startArrow = "block" if bidirectional else "none"
    edge.strokeColor = "#545B64"
    return edge


def build_diagram():
    file = drawpyo.File()
    file.file_name = "architecture.drawio"
    file.file_path = OUTPUT_DIR

    page = drawpyo.Page(file=file)
    page.name = "Serverless Semantic Search Assistant"

    user = add_node(page, "User", 20, 220, "client", "#232F3E")
    web_app = add_node(page, "Web app", 180, 220, "lambda_function", "#ED7100")

    authentication = add_node(page, "Authentication", 180, 60, "cognito", "#DD344C")
    authorizer = add_node(page, "Authorizer", 340, 60, "lambda_function", "#ED7100")

    rest_api = add_node(page, "REST API", 340, 220, "api_gateway", "#E7157B")
    api_call = add_node(page, "API call", 500, 220, "lambda_function", "#ED7100")

    access_models = add_node(page, "Access\nmodels", 660, 220, "machine_learning", "#01A88D")

    ai_group = add_group(page, "", 800, 90, 200, 160)
    ai_model = add_node(page, "AI Model", 840, 130, "bedrock", "#01A88D")

    semantic_search = add_node(page, "Semantic\nsearch", 800, 340, "machine_learning", "#01A88D")
    vector_db = add_node(page, "Vector\ndatabase", 960, 340, "opensearch_service", "#C925D1")

    documents = add_plain_node(page, "Enterprise\ndocuments", 800, 480)

    add_edge(page, user, web_app, "Login / Response", bidirectional=True)
    add_edge(page, web_app, authentication, "Authenticate user")
    add_edge(page, web_app, rest_api, "Request / Response", bidirectional=True)
    add_edge(page, rest_api, authorizer, "Authorize request")
    add_edge(page, rest_api, api_call, "Request / Response", bidirectional=True)
    add_edge(page, api_call, access_models, "Request / Response", bidirectional=True)

    add_edge(page, access_models, ai_model, "Prompt + retrieved data")
    add_edge(page, ai_model, access_models, "Response")

    add_edge(page, access_models, semantic_search, "Prompt")
    add_edge(page, semantic_search, access_models, "Response")

    add_edge(page, semantic_search, vector_db, "Retrieved data", bidirectional=True)
    add_edge(page, documents, vector_db, "Ingest data")

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    file.write()
    print(f"Wrote {os.path.join(OUTPUT_DIR, file.file_name)}")


if __name__ == "__main__":
    build_diagram()
