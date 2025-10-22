#!/usr/bin/env python3
"""
parse-diff-files.py
Script to parse diff file paths and extract filename and range information
Usage: python3 parse-diff-files.py <comma_separated_diff_files>
"""

import sys
import os
import re

def parse_diff_file_path(file_path):
    """
    Parse a diff file path to extract filename and range information.
    
    Args:
        file_path (str): Full path to the diff file
        
    Returns:
        dict: Dictionary containing filename, range, full path, and content
    """
    # Extract filename from path
    filename = os.path.basename(file_path)
    
    # Remove .diff extension
    base_filename = filename.replace('.diff', '')
    
    # Extract range using regex pattern: filename.range.diff
    # Pattern matches: filename.1-292.diff -> range = "1-292"
    range_pattern = r'\.(\d+-\d+)\.diff$'
    range_match = re.search(range_pattern, filename)
    
    # Read file content
    content = ""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except (FileNotFoundError, PermissionError, UnicodeDecodeError) as e:
        content = f"Error reading file: {e}"
    
    if range_match:
        range_str = range_match.group(1)
        start_line, end_line = range_str.split('-')
        return {
            'filename': base_filename.replace(f'.{range_str}', ''),
            'range': range_str,
            'start_line': int(start_line),
            'end_line': int(end_line),
            'full_path': file_path,
            'content': content
        }
    else:
        # If no range pattern found, return basic info
        return {
            'filename': base_filename,
            'range': None,
            'start_line': None,
            'end_line': None,
            'full_path': file_path,
            'content': content
        }

def main():
    if len(sys.argv) != 2:
        print("Usage: python3 parse-diff-files.py <comma_separated_diff_files>")
        print("Example: python3 parse-diff-files.py '/path/file.1-292.diff,/path/file.292-29999.diff'")
        sys.exit(1)
    
    # Get input from command line argument
    input_files = sys.argv[1]
    
    # Split by comma and strip whitespace
    file_paths = [path.strip() for path in input_files.split(',')]
    
    # Process each file path
    for file_path in file_paths:
        if not file_path:
            continue
            
        parsed_info = parse_diff_file_path(file_path)
        
        # Output information for each file
        print(f"{parsed_info['filename']}")
        if parsed_info['range']:
            print(f"Range: {parsed_info['range']} (lines {parsed_info['start_line']}-{parsed_info['end_line']})")
        else:
            print("Range: No range found")
        print(f"Path: {parsed_info['full_path']}")
        print("Content:")
        print(parsed_info['content'])
        print("=" * 80)

if __name__ == "__main__":
    main()
