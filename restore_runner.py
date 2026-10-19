import subprocess
from pathlib import Path
p = Path('skill_core/runtime/preview_runner.gd')
p.write_bytes(subprocess.check_output(['git', 'show', 'HEAD:skill_core/runtime/preview_runner.gd']))
