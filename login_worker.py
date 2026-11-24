"""Run NEU's web SSO login only when the gateway says this client is offline."""
import json
import re
import sys
from time import sleep
from pathlib import Path
from urllib.parse import urljoin, urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))

from ipgw.core.api.SSO_error import BackendError
from ipgw.core.api import SSO as sso_api
from ipgw.core.api.portal import get_info
from ipgw.core.errors_modals import LoginResult
from ipgw.core.ipgw import IPGW
from ipgw.core.prepare_session import prepare_session


def enable_new_sso_script():
    """NEU renamed its login script; keep the upstream extractor for old pages."""
    upstream = sso_api.extract_login_page_rsa_public_key
    if getattr(upstream, "_supports_new_neu_script", False):
        return

    def extract(session, page_soup):
        try:
            return upstream(session, page_soup)
        except BackendError as exc:
            if exc.page != "cannot find login_neu.js from SSO login page":
                raise
        for script in page_soup.find_all("script", src=True):
            source = script.get("src", "")
            if not urlsplit(source).path.endswith("/login_neu_new.js"):
                continue
            script_url = urljoin("https://pass.neu.edu.cn", source)
            parsed = urlsplit(script_url)
            if parsed.scheme != "https" or parsed.hostname != "pass.neu.edu.cn":
                raise BackendError("unexpected SSO script host")
            response = session.get(script_url)
            response.raise_for_status()
            match = re.search(r'publicKeyStr\s*=\s*"([^"]+)"', response.text)
            if not match:
                raise BackendError("cannot extract publicKeyStr from login_neu_new.js")
            return match.group(1)
        raise BackendError("cannot find a supported NEU login script")

    extract._supports_new_neu_script = True
    sso_api.extract_login_page_rsa_public_key = extract


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
        enable_new_sso_script()
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

