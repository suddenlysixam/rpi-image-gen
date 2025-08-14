#!/usr/bin/env python3

# Minimal doc generator for layers

import os
import sys
from pathlib import Path
from jinja2 import Environment, FileSystemLoader
import markdown

script_dir = Path(__file__).parent
sys.path.insert(0, str(script_dir.parent / 'site'))
from layer_manager import LayerManager
from validators import get_validator_documentation_data

def main():
    script_dir = Path(__file__).parent  # The docs/ directory
    doc_dir = script_dir  # Generate in the docs directory
    layer_dir = doc_dir / 'layer'  # Layer documentation subdirectory
    templates_dir = script_dir.parent / 'templates' / 'docs'  # ../templates/doc

    # jinja init
    env = Environment(loader=FileSystemLoader(str(templates_dir)))

    # Load layers
    layer_paths = [
        str(script_dir.parent / 'device'),
        str(script_dir.parent / 'image'),
        str(script_dir.parent / 'meta')
    ]
    manager = LayerManager(layer_paths)

    # All layer names
    layer_names = sorted(manager.layers.keys())

    # Do it
    layer_template = env.get_template('layer.html')
    layers_info = []

    for layer_name in layer_names:
        doc_data = manager.get_layer_documentation_data(layer_name)
        if doc_data:
            # If present, convert companion doc to HTML
            if doc_data.get('companion_doc'):
                # Assume markdown format
                doc_data['companion_html'] = markdown.markdown(
                    doc_data['companion_doc'],
                    extensions=['tables', 'fenced_code', 'toc']
                )
            else:
                doc_data['companion_html'] = ""

            # Render layer page
            html_content = layer_template.render(layer=doc_data)

            # Write layer page
            layer_file = layer_dir / f"{layer_name}.html"
            layer_file.write_text(html_content)

            # Collect info for index
            layers_info.append({
                'name': layer_name,
                'description': doc_data['layer_info'].get('description', 'No description'),
                'category': doc_data['layer_info'].get('category', 'uncategorised'),
                'filename': f"layer/{layer_name}.html"
            })

            print(f"Generated: {layer_file}")

    # Generate index page
    index_md = script_dir / 'index.md'
    if index_md.exists():
        md_content = index_md.read_text()
        md = markdown.Markdown(extensions=['extra', 'codehilite'])
        index_content = md.convert(md_content)
    else:
        # Empty static fallback
        index_content = ""

    # Render index page
    index_template = env.get_template('index.html')
    index_html = index_template.render(
        content=index_content,
        layers=layers_info
    )

    # Write index page
    index_file = doc_dir / 'index.html'
    index_file.write_text(index_html)
    print(f"Generated: {index_file}")

    # Generate validation help page
    help_template = env.get_template('variable-validation.html')
    validation_data = get_validator_documentation_data()

    vars_html = help_template.render(validation=validation_data)
    vars_file = doc_dir / 'variable-validation.html'
    vars_file.write_text(vars_html)
    print(f"Generated: {vars_file}")

    print(f"\nDocumentation generated in {doc_dir}/")

if __name__ == '__main__':
    main()
