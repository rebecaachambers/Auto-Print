#!/usr/bin/env python3
"""imagetoraster wrapper: convert image to PDF, center photos, then rasterize.
Replaces /usr/lib/cups/filter/imagetoraster to intercept iPhone/AirPrint photo jobs.
"""
import sys, os, subprocess, tempfile

def main():
    args = sys.argv[1:]
    fname = args[5] if len(args) > 5 and args[5] != "-" else None
    
    # Get source image
    if fname and os.path.exists(fname):
        img_src = fname
    else:
        tmp = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
        tmp.write(sys.stdin.buffer.read())
        img_src = tmp.name
        tmp.close()

    # Step 1: Image -> PDF via imagetopdf
    pdf_tmp = tempfile.NamedTemporaryFile(suffix=".pdf", delete=False)
    pdf_path = pdf_tmp.name
    pdf_tmp.close()
    
    r1 = subprocess.run(["/usr/lib/cups/filter/imagetopdf"] + args[:5] + [img_src],
                        capture_output=True, timeout=60)
    with open(pdf_path, "wb") as f:
        f.write(r1.stdout)

    # Step 2: Detect if photo (little extractable text)
    r2 = subprocess.run(["pdftotext", pdf_path, "-"], capture_output=True, text=True, timeout=10)
    is_photo = len(r2.stdout.strip()) < 30

    if is_photo and os.path.exists("/usr/local/bin/center-filter.py"):
        # Step 3: Center the PDF on page
        centered_tmp = tempfile.NamedTemporaryFile(suffix=".pdf", delete=False)
        centered_path = centered_tmp.name
        centered_tmp.close()
        
        r3 = subprocess.run(["python3", "/usr/local/bin/center-filter.py"] + args[:5] + [pdf_path],
                            capture_output=True, timeout=60)
        with open(centered_path, "wb") as f:
            f.write(r3.stdout)
        render_path = centered_path
        extra_cleanup = [pdf_path, centered_path]
    else:
        render_path = pdf_path
        extra_cleanup = [pdf_path]

    # Step 4: PDF -> CUPS raster via gstoraster (pass FILE path, not stdin)
    r4 = subprocess.run(["/usr/lib/cups/filter/gstoraster"] + args[:5] + [render_path],
                        capture_output=True, timeout=120)
    sys.stdout.buffer.write(r4.stdout)
    sys.stdout.buffer.flush()

    # Cleanup
    for p in extra_cleanup:
        if p != fname:
            try: os.unlink(p)
            except: pass

if __name__ == "__main__":
    main()
