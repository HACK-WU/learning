"""Slack 入口。

注意（课 8 实测）：Slack 通道的回调地址带 /v1 前缀，
真实地址是 /v1/channels/slack/events，不是文档写的 /channels/slack/events。
注册到 Slack 后台时用前者，否则 404。

本文件只写声明：入站解析、出站回话、机器人供给都由平台代办，
这就是 Slack 通道和 HTTP 通道最大的差别 —— HTTP 通道要自己写 verify/parse。
"""

from managed_deepagents import channels

channel = channels.slack(name="Duty Assistant")
