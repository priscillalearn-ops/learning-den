import subprocess, sys, os, shutil, time
SP=os.path.dirname(os.path.abspath(__file__))
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for sc in sys.argv[1:]:
    ud=f"{SP}/chrome-{sc}"; shutil.rmtree(ud, ignore_errors=True)
    out=f"{SP}/shots/{sc}.png"
    if os.path.exists(out): os.remove(out)
    p=subprocess.Popen([CH,"--headless=new","--disable-gpu","--hide-scrollbars","--no-first-run","--no-default-browser-check",
        "--window-size=390,844","--force-device-scale-factor=3","--timeout=4500",f"--user-data-dir={ud}",
        f"--screenshot={out}",f"file://{SP}/app.html#{sc}"],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    for _ in range(60):
        time.sleep(0.5)
        if os.path.exists(out) and os.path.getsize(out)>0: time.sleep(1); break
    p.kill(); subprocess.run(["pkill","-f",ud]); shutil.rmtree(ud, ignore_errors=True)
    print(sc, os.path.getsize(out) if os.path.exists(out) else "missing")
