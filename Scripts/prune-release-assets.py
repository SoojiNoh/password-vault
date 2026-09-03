#!/usr/bin/env python3
"""릴리스에 남아 있는 옛 첨부 파일을 지웁니다.

파일 이름을 한 번 바꾸면 예전 이름의 파일이 릴리스에 그대로 남습니다.
사용자는 릴리스 화면에서 어느 것을 받아야 할지 알 수 없게 되므로,
지금 올릴 파일 하나만 남기고 정리합니다.

(깃허브는 첨부 파일 이름에서 한글 같은 글자를 지워 버립니다.
 그래서 예전에 올라간 한글 이름 파일은 `-.-macOS.zip` 처럼 남아 있습니다.)

사용법:  prune-release-assets.py <태그> <남길 파일 이름>
환경변수: GH_TOKEN, REPO (owner/repo 형식)

이 스크립트는 실패해도 빌드를 막지 않습니다. 정리는 있으면 좋은 일이지
꼭 되어야 하는 일은 아니기 때문입니다.
"""

import json
import os
import sys
import urllib.error
import urllib.request

API = "https://api.github.com"


def call(method: str, url: str, token: str):
    request = urllib.request.Request(url, method=method)
    request.add_header("Authorization", f"Bearer {token}")
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("X-GitHub-Api-Version", "2022-11-28")
    return urllib.request.urlopen(request, timeout=30)


def main() -> int:
    if len(sys.argv) != 3:
        print("사용법: prune-release-assets.py <태그> <남길 파일 이름>", file=sys.stderr)
        return 2

    tag, keep = sys.argv[1], sys.argv[2]
    token = os.environ.get("GH_TOKEN", "")
    repo = os.environ.get("REPO", "")

    if not token or not repo:
        print("GH_TOKEN 또는 REPO 가 없어 정리를 건너뜁니다.")
        return 0

    try:
        with call("GET", f"{API}/repos/{repo}/releases/tags/{tag}", token) as response:
            release = json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            print(f"'{tag}' 릴리스가 아직 없습니다. 지울 것이 없습니다.")
        else:
            print(f"릴리스를 읽지 못했습니다: {error}", file=sys.stderr)
        return 0
    except Exception as error:  # 네트워크 문제 등
        print(f"릴리스를 읽지 못했습니다: {error}", file=sys.stderr)
        return 0

    stale = [asset for asset in release.get("assets", []) if asset.get("name") != keep]
    if not stale:
        print("지울 옛 파일이 없습니다.")
        return 0

    for asset in stale:
        name = asset.get("name", "?")
        try:
            call("DELETE", f"{API}/repos/{repo}/releases/assets/{asset['id']}", token).close()
            print(f"옛 파일을 지웠습니다: {name}")
        except Exception as error:
            print(f"지우지 못했습니다({name}): {error}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
