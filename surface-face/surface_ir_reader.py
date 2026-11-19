# Howdy recorder for the Surface Pro 7 IR camera (OV7251 on the IPU4P, driven
# by the paicheck/surfacepro7-camera-ir stack, see dotfiles surface-camera/).
#
# Based on surface-kit's surface_ir_reader.py (linux-surface discussion #1353),
# adapted to this driver's media graph: sensor -> CSI-2 1 -> CSI2 BE SOC ->
# BE SOC capture 0, raw Y10. Each start wires the pipeline itself, sets the
# analogue gain, and streams through v4l2-ctl. Frames are 10-bit in 16-bit
# words; they are stretched to 8 bits, turned upright (the sensor is mounted a
# quarter turn off) and handed over as BGR like any other Howdy recorder.
#
# The IR emitter is driven by the sensor strobe while streaming
# (ov7251 strobe_pattern=255, set in /etc/modprobe.d/surface-camera.conf).
import subprocess

import cv2
import numpy as np

CSI2 = "Intel IPU4 CSI-2 1"
BE = "Intel IPU4 CSI2 BE SOC"
CAPTURE = "Intel IPU4 BE SOC capture 0"
WIDTH, HEIGHT = 640, 480
FMT = f"Y10_1X10/{WIDTH}x{HEIGHT}"
FRAME_BYTES = WIDTH * HEIGHT * 2
# About 4x (16 = 1x); surface-kit measured this on a face at 40 cm, emitter on
GAIN = 64
# The links are MEDIA_LNK_FL_DYNAMIC (0x4); keep that bit when enabling
DYN_ENABLED = 5


def _run(*args):
	return subprocess.run(args, check=True, capture_output=True, text=True).stdout


class surface_ir_reader:
	def __init__(self, media="/dev/media0"):
		self.media = media if media and media != "none" else "/dev/media0"
		self.proc = None

	def _ml(self, *args):
		return _run("media-ctl", "-d", self.media, *args)

	def _start(self):
		graph = self._ml("-p")
		sensor = next(line.split(": ", 1)[1].split(" (")[0]
		              for line in graph.splitlines()
		              if line.startswith("- entity") and ": ov7251" in line)
		self._ml("-V", f'"{sensor}":0 [fmt:{FMT}]')
		self._ml("-V", f'"{CSI2}":0 [fmt:{FMT}]')
		self._ml("-V", f'"{CSI2}":1 [fmt:{FMT}]')
		self._ml("-l", f'"{sensor}":0 -> "{CSI2}":0 [1]')
		self._ml("-l", f'"{CSI2}":1 -> "{BE}":0 [{DYN_ENABLED}]')
		self._ml("-l", f'"{BE}":8 -> "{CAPTURE}":0 [{DYN_ENABLED}]')
		self._ml("-V", f'"{BE}":0 [fmt:{FMT}]')
		self._ml("-V", f'"{BE}":8 [fmt:{FMT}]')
		subdev = self._ml("-e", sensor).strip()
		video = self._ml("-e", CAPTURE).strip()
		_run("v4l2-ctl", "-d", subdev, "--set-ctrl", f"analogue_gain={GAIN}")
		self.proc = subprocess.Popen(
			["v4l2-ctl", "-d", video,
			 f"--set-fmt-video=width={WIDTH},height={HEIGHT},pixelformat=Y10 ",
			 "--stream-mmap=4", "--stream-to=-"],
			stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)

	def isOpened(self):
		return self.proc is not None and self.proc.poll() is None

	def get(self, prop):
		# Sizes as seen after the quarter turn
		if prop == cv2.CAP_PROP_FRAME_WIDTH:
			return HEIGHT
		if prop == cv2.CAP_PROP_FRAME_HEIGHT:
			return WIDTH
		return 0

	def set(self, prop, value):
		return False

	def grab(self):
		ret, _ = self.read()
		return ret

	def read(self):
		if self.proc is None:
			try:
				self._start()
			except (subprocess.CalledProcessError, OSError, StopIteration):
				return False, None
		raw = self.proc.stdout.read(FRAME_BYTES)
		if raw is None or len(raw) != FRAME_BYTES:
			return False, None
		frame = np.frombuffer(raw, dtype="<u2").reshape(HEIGHT, WIDTH).astype(np.float32)
		top = max(float(np.percentile(frame, 99.5)), 1.0)
		frame = np.clip(frame * (255.0 / top), 0, 255).astype(np.uint8)
		frame = cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
		return True, cv2.cvtColor(frame, cv2.COLOR_GRAY2BGR)

	def release(self):
		if self.proc is not None:
			self.proc.terminate()
			try:
				self.proc.wait(timeout=5)
			except subprocess.TimeoutExpired:
				self.proc.kill()
				self.proc.wait()
			self.proc.stdout.close()
			self.proc = None
