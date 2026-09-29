@echo off
rem Step 0 of the 3D move: walk around the code-made street (Forward+).
cd /d "%~dp0..\.."
start "" "C:\Users\Miler\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe" --path . --rendering-method forward_plus res://tests/look3d/play3d.tscn
