#!/usr/bin/env python3
"""把 WebUI 里关键文件的 SHA-256 写进 iCar/WebHashes.swift（App 启动时自检）。

只在构建时运行；网页改了没重新生成，App 会认为资源被改过。
"""
import hashlib, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(ROOT, 'iCar', 'WebUI')
TARGETS = [
    'index.html',
    'js/app.js',
    'js/viewer3d.js',
    'js/overlay.js',
    'css/app.css',
]

lines = []
for rel in TARGETS:
    p = os.path.join(WEB, rel)
    with open(p, 'rb') as f:
        h = hashlib.sha256(f.read()).hexdigest()
    lines.append(f'        "{rel}": "{h}",')

out = '''import Foundation

/// 构建时由 scripts/gen-web-hashes.py 生成。启动时拿它和包里的网页文件比对。
enum WebHashes {
    static let map: [String: String] = [
''' + "\n".join(lines) + '''
    ]
}
'''
dst = os.path.join(ROOT, 'iCar', 'WebHashes.swift')
with open(dst, 'w') as f:
    f.write(out)
print('wrote', dst)
