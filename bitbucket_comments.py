#!/usr/bin/env python3
"""
Bitbucket Line Comments - Post inline comments from diff files
"""

import argparse
import sys
import base64
import re
from typing import List, Dict, Optional
import requests
from dotenv import load_dotenv
import os

# Load environment variables
load_dotenv()


class BitbucketClient:
    """Client for interacting with Bitbucket REST API v1"""
    
    def __init__(self):
        self.server = os.getenv('BITBUCKET_SERVER', 'https://api.bitbucket.org/1.0')
        self.workspace = os.getenv('BITBUCKET_WORKSPACE', '')
        self.repo = os.getenv('BITBUCKET_REPO', '')
        self.username = os.getenv('BITBUCKET_USERNAME', '')
        self.app_password = os.getenv('BITBUCKET_APP_PASSWORD', '')
        
        if not all([self.workspace, self.repo, self.username, self.app_password]):
            raise ValueError(
                "Missing required environment variables. "
                "Please set BITBUCKET_WORKSPACE, BITBUCKET_REPO, BITBUCKET_USERNAME, and BITBUCKET_APP_PASSWORD"
            )
        
        # Create base64 authentication header
        credentials = f"{self.username}:{self.app_password}"
        encoded_credentials = base64.b64encode(credentials.encode()).decode()
        self.headers = {
            'Authorization': f'Basic {encoded_credentials}',
            'Content-Type': 'application/json',
            'Accept': 'application/json'
        }
    
    def test_connection(self) -> bool:
        """Test connection to Bitbucket (using API v1)"""
        try:
            url = f"{self.server}/user"
            response = requests.get(url, headers=self.headers, timeout=10)
            response.raise_for_status()
            user_info = response.json()
            print(f"✓ Connected to Bitbucket as: {user_info.get('display_name', self.username)}")
            return True
        except Exception as e:
            print(f"✗ Connection failed: {str(e)}")
            return False
    
    def post_inline_comment(
        self, 
        pr_id: int, 
        file_path: str, 
        line: int, 
        comment_text: str
    ) -> bool:
        """
        Post an inline comment to a Bitbucket pull request (API v1)
        
        Args:
            pr_id: Pull request number
            file_path: Path to file in repository
            line: Line number to comment on
            comment_text: Comment text
            
        Returns:
            bool: True if successful, False otherwise
        """
        try:
            url = f"{self.server}/repositories/{self.workspace}/{self.repo}/pullrequests/{pr_id}/comments"
            
            # v1 API format
            payload = {
                "content": comment_text,
                "line_to": line,
                "filename": file_path
            }
            
            response = requests.post(
                url,
                headers=self.headers,
                json=payload,
                timeout=30
            )
            
            if response.status_code in [200, 201]:
                return True
            else:
                print(f"✗ Failed to post comment: {response.text}")
                return False
                
        except requests.exceptions.RequestException as e:
            print(f"✗ Error posting comment: {str(e)}")
            return False


def parse_diff_file(file_path: str) -> Optional[Dict]:
    """
    Parse a diff file path to extract filename, range, and content.
    
    Args:
        file_path: Full path to the diff file
        
    Returns:
        dict: Dictionary containing filename, range, lines, and content
    """
    if not os.path.exists(file_path):
        print(f"✗ Diff file not found: {file_path}")
        return None
    
    # Extract filename from path
    filename = os.path.basename(file_path)
    
    # Remove .diff extension
    base_filename = filename.replace('.diff', '')
    
    # Extract range using regex pattern: filename.range.diff
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
        start_line, end_line = map(int, range_str.split('-'))
        return {
            'filename': base_filename.replace(f'.{range_str}', ''),
            'range': range_str,
            'start_line': start_line,
            'end_line': end_line,
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


def parse_diff_files(comma_separated_paths: str) -> List[Dict]:
    """
    Parse comma-separated diff file paths.
    
    Args:
        comma_separated_paths: Comma-separated list of diff file paths
        
    Returns:
        list: List of parsed diff file information
    """
    # Split by comma and strip whitespace
    file_paths = [path.strip() for path in comma_separated_paths.split(',')]
    
    results = []
    
    # Process each file path
    for file_path in file_paths:
        if not file_path:
            continue
            
        parsed_info = parse_diff_file(file_path)
        if parsed_info:
            results.append(parsed_info)
    
    return results


def format_comment(comment: str, filename: str, line: Optional[int]) -> str:
    """
    Format comment text with file and line reference
    
    Args:
        comment: Base comment text
        filename: File name
        line: Line number (optional)
        
    Returns:
        str: Formatted comment
    """
    parts = [comment]
    
    if filename:
        parts.append(f"File: `{filename}`")
    
    if line is not None:
        parts.append(f"Line: {line}")
    
    return "\n".join(parts)


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Post inline comments to Bitbucket pull requests from diff files',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # From diff files
  python bitbucket_comments.py --pr 123 --diff-files "file.1-42.diff,file.42-100.diff"
  
  # With custom comment
  python bitbucket_comments.py --pr 123 --diff-files "file.1-42.diff" --comment "Code review finding"
  
  # Multiple diff files
  python bitbucket_comments.py --pr 123 --diff-files "src/main.py.1-42.diff,src/utils.py.15-67.diff"
        """
    )
    
    parser.add_argument('--pr', type=int, required=True, help='Pull request number')
    parser.add_argument('--diff-files', dest='diff_files', required=True, help='Comma-separated diff file paths (e.g., "file.1-42.diff,file.42-100.diff")')
    parser.add_argument('--comment', help='Comment text (optional, defaults to "Code review finding")')
    parser.add_argument('--test', action='store_true', help='Test connection without posting')
    
    args = parser.parse_args()
    
    # Initialize Bitbucket client
    try:
        bb_client = BitbucketClient()
    except ValueError as e:
        print(f"✗ {str(e)}")
        sys.exit(1)
    
    # Test connection if requested
    if args.test:
        success = bb_client.test_connection()
        sys.exit(0 if success else 1)
    
    # Parse diff files
    diff_data = parse_diff_files(args.diff_files)
    
    if not diff_data:
        print("✗ No valid diff files found")
        sys.exit(1)
    
    # Default comment
    default_comment = args.comment or "Code review finding"
    
    # Post comment for each diff file
    success_count = 0
    for diff in diff_data:
        comment_text = format_comment(
            default_comment,
            diff['filename'],
            diff['start_line'] if diff['range'] else None
        )
        
        # Extract a snippet from diff content for the comment
        if diff['content'] and '+++' in diff['content']:
            # Extract first few lines of diff as context
            diff_lines = diff['content'].split('\n')[:8]
            snippet = '\n'.join(diff_lines)
            comment_text = f"{comment_text}\n\n```\n{snippet}\n```"
        
        line_number = diff['start_line'] if diff['range'] else 1
        
        print(f"Posting comment to PR #{args.pr} for {diff['filename']} at line {line_number}...")
        
        success = bb_client.post_inline_comment(
            args.pr,
            diff['filename'],
            line_number,
            comment_text
        )
        
        if success:
            print(f"✓ Comment posted successfully for {diff['filename']}")
            success_count += 1
        else:
            print(f"✗ Failed to post comment for {diff['filename']}")
    
    if success_count == len(diff_data):
        print(f"\n✓ Posted all {success_count} comments successfully")
        sys.exit(0)
    else:
        print(f"\n✗ Posted {success_count}/{len(diff_data)} comments")
        sys.exit(1)


if __name__ == '__main__':
    main()