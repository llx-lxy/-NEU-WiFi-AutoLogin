"""Run NEU's web SSO login only when the gateway says this client is offline."""
import json
import sys
from time import sleep
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))

from ipgw.core.api.SSO_error import BackendError
from ipgw.core.api.portal import get_info
from ipgw.core.errors_modals import LoginResult
from ipgw.core.ipgw import IPGW
from ipgw.core.prepare_session import prepare_session


def status():
    session = prepare_session(bypass_proxy=True)
    result = get_info(session)
    return result.get("error", "unknown")


def main():
    try:
        auth = json.loads(sys.stdin.readline())
        username = auth["username"]
        password = auth["password"]
        current = status()
        if current == "ok":
            print("已在线")
            return 0
        if current != "not_online_error":
            print("网关状态异常：" + str(current)[:80])
            return 3
        for attempt in range(2):
            try:
                client = IPGW(bypass_proxy=True)
                result = client.login(username, password)
                break
            except BackendError:
                # The SSO POST can return an error page after authentication took effect.
                if status() == "ok":
                    print("统一身份认证已生效，校园网已连接")
                    return 0
                if attempt == 0:
                    sleep(2)
                    continue
                print("统一身份认证服务返回异常页面，请稍后重试")
                return 3
        if result == LoginResult.LoginSuccessful:
            if status() == "ok":
                print("统一身份认证成功，校园网已连接")
                return 0
            print("认证已提交，但网关暂未确认在线，请稍后重试")
            return 3
        print("认证结果：" + result.name)
        if result in (LoginResult.UsernameOrPasswordError, LoginResult.ArrearageUserError):
            return 2
        return 3
    except Exception as exc:
        # Never include exception messages: upstream URLs can contain login tickets.
        print("认证或网关查询失败：" + type(exc).__name__)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())

