# เสียงที่ต้องหา (รายการสำหรับไปฟังเลือก)

ไล่ครบทุกระบบในเกมแล้ว (2026-09-28): 9 ชุด เรียงจากสำคัญมากไปน้อย · ชุด 1–3 ทำให้เกมดีขึ้นมากที่สุด
ชุด 5–9 ส่วนใหญ่ "ใช้ได้อยู่แล้วแต่ไม่ตรง" ค่อย ๆ หามาแทนได้ · เสียงใหม่ที่ต้องมีโค้ดเพิ่ม (แตร เปิดปิดกระเป๋า) Claude ทำให้ตอนใส่

## วิธีส่งเสียงเข้าเกม
1. ฟังแล้วชอบ โหลดมา (mp3 / wav / ogg อะไรก็ได้)
2. ตั้งชื่อไฟล์ตาม **รหัส** ในตาราง + ลำดับ เช่น `runner_alert_1.mp3`, `runner_alert_2.wav`
3. วางไว้ในโฟลเดอร์ `audio/incoming/`
4. จดที่มาใน `audio/incoming/SOURCES.txt` บรรทัดละไฟล์: `ชื่อไฟล์ | ลิงก์หน้าเสียง | สัญญาอนุญาต`
   เช่น `runner_alert_1.mp3 | https://pixabay.com/sound-effects/xxxx | Pixabay License`
5. บอก Claude: จะแปลงเป็น ogg, ปรับความดังให้เท่ากันทั้งชุด, ตัดช่วงเงียบหัวท้าย, ใส่เข้าเกม และลงชื่อใน CREDITS.md ให้

**สัญญาที่ใช้ได้:** CC0 · Pixabay License · CC-BY (ต้องใส่ชื่อ: จดชื่อผู้สร้างด้วย)
**ห้ามใช้:** NC (ห้ามใช้เชิงพาณิชย์) · "personal use only" · เสียงจาก YouTube หรือเกมอื่น

**แหล่งค้น:** Pixabay (sound effects) · Freesound.org (กรอง License = CC0) · OpenGameArt (CC0) · Kenney.nl

**เคล็ดลับการเลือก:** เลือกเสียง "แห้ง" ที่อัดใกล้ ๆ ไม่มีเสียงสะท้อนห้องหรือดนตรีปน ·
ยิ่งมีหลายเวอร์ชันของเสียงเดียวกัน (คนละตัว คนละครั้ง) ยิ่งดี ไม่ซ้ำจนน่าเบื่อ ·
ถ้าไฟล์เดียวมีหลายเสียงต่อกัน โหลดมาได้เลย เดี๋ยวตัดแยกให้

---

## ⭐ ชุดที่ 1: ซอมบี้ (ทำก่อน · ได้ผลมากสุด)

| รหัส | ใช้ตอน | อารมณ์ที่ต้องการ | คำค้น (อังกฤษ) | จำนวน | ยาว |
|---|---|---|---|---|---|
| `zombie_idle` | ซอมบี้ธรรมดายืนหรือเดินเฉย ๆ | ครางต่ำ ลากยาว เหนื่อย ไม่ดุ | zombie groan, zombie moan | 6–10 | 1–3 วิ |
| `zombie_alert` ✅ 1 | ซอมบี้เห็นเรา (ขึ้น !) | สะดุ้งคำราม สั้น ดังขึ้น | zombie growl, zombie alert, zombie snarl | 4–6 | 0.5–1.5 วิ |
| `zombie_attack` | ง้างตัวพุ่งกัด | คำรามแรง ฉับไว | zombie attack, zombie lunge | 4–6 | 0.3–1 วิ |
| `zombie_bite` | กัดโดนเรา | เสียงฟันกับเนื้อ เปียก ๆ | flesh bite, chomp, gore bite | 3–5 | 0.2–0.6 วิ |
| `zombie_death` | ซอมบี้ตาย | ลมหายใจสุดท้าย ครางแล้วเงียบ | zombie death, dying gurgle | 4–6 | 0.5–1.5 วิ |
| `runner_alert` | ตัววิ่งเห็นเรา | กรีดแหลม ร้องแบบคลั่ง | zombie shriek, fast zombie scream | 3–4 | 0.5–1.5 วิ |
| `runner_breath` | ตัววิ่งวิ่งไล่ | หอบถี่ ๆ แหบ ๆ | ragged breathing, panting creature | 2–3 | 1–2 วิ (วนได้) |
| `fat_idle` | ตัวอ้วนเดิน | ครางต่ำมาก ทุ้ม เปียก เหมือนมีน้ำในคอ | deep monster groan, gurgling growl | 3–5 | 1–3 วิ |
| `screamer_scream` | ตัวกรีดร้องเรียกพวก | กรีดยาว แหลม ขนลุก | horror scream, banshee scream | 2–3 | 1.5–3 วิ |
| `junkie_laugh` | ตัวติดยาเห็นเรา | หัวเราะคลั่ง หึ ๆ แหบ ๆ | crazy laugh, maniac giggle | 3–4 | 1–2 วิ |
| `faker_rise` | ศพปลอมลุกขึ้น | สะดุดลมหายใจ เฮือก! | gasp, sudden breath, zombie wake | 2–3 | 0.5–1 วิ |
| `guard_whistle` | ยามเป่านกหวีด | นกหวีด รปภ. จริง ๆ เป่ายาว | referee whistle, police whistle | 2–3 | 0.5–1.5 วิ |
| `crawler_drag` | ซอมบี้คลานขาขาด | ลากตัวบนพื้น ครูดเสื้อผ้า | body drag, crawling scrape | 2–3 | 1–2 วิ (วนได้) |

**ถ้าหาได้ไม่ครบ ไม่เป็นไร** ชนิดไหนไม่มีเสียงของตัวเอง เกมจะใช้เสียงของซอมบี้ธรรมดาแทน

## ชุดที่ 2: ตัวเรา
| รหัส | ใช้ตอน | อารมณ์ | คำค้น | จำนวน |
|---|---|---|---|---|
| `player_hurt` | โดนกัดหรือตี | ร้องเจ็บสั้น ๆ (ชายและหญิง ถ้าได้) | pain grunt, hurt male, hurt female | 4–6 |
| `player_tired` | เหนื่อยหอบ | หายใจหอบ | heavy breathing, out of breath | 2–3 |
| `player_eat` / `player_drink` | กินหรือดื่ม | เคี้ยว กลืน ซดน้ำ | eating crunch, drinking gulp | 2–3 ต่ออย่าง |

## ชุดที่ 3: อาวุธ (เปลี่ยนเสียงที่สร้างจากโค้ด)
| รหัส | ใช้ตอน | คำค้น | จำนวน |
|---|---|---|---|
| `gun_pistol` | ยิงปืนพก | pistol shot, handgun gunshot | 3–4 |
| `gun_shotgun` | ยิงลูกซอง | shotgun blast | 2–3 |
| `gun_reload` | บรรจุกระสุน | pistol reload, magazine insert | 2 |
| `knife_stab` | แทงมีด | knife stab flesh | 3–4 |
| `machete_chop` | ฟันมีดพร้าหรือขวาน | machete chop, axe hit flesh | 3–4 |

## ชุดที่ 4: บรรยากาศเมืองไทย (เล่นเบา ๆ อยู่ไกล ๆ)
| รหัส | คืออะไร | คำค้น |
|---|---|---|
| `amb_gecko` | ตุ๊กแกร้องกลางคืน | tokay gecko call |
| `amb_cicada` | จักจั่นกลางวัน | cicadas summer |
| `amb_frogs` | กบในคลองหลังฝนตก | frogs croaking night |
| `amb_soi_dog` | หมาในซอยเห่าไกล ๆ | distant dog barking |
| `amb_moto_far` | มอไซค์วิ่งผ่านไกล ๆ (ผู้รอดคนอื่น?) | distant motorcycle pass |
| `amb_temple_bell` | ระฆังวัดไกล ๆ | temple bell distant |
| `amb_thunder` | ฟ้าร้องตอนฝนตก | thunder rumble distant |
| `amb_rain_roof` | ฝนตกบนหลังคาสังกะสี (ตอนอยู่ในบ้าน) | rain on tin roof, rain on metal roof |
| `amb_pa_speaker` | เสียงตามสายที่เสียแล้ว เสียงแตก ๆ ไกล ๆ | distorted PA announcement, broken loudspeaker |

## ชุดที่ 5: ตัวเราทำสิ่งต่าง ๆ (ตอนนี้ยืมเสียงอื่นอยู่ หรือเงียบ)
| รหัส | ใช้ตอน | ตอนนี้ | คำค้น | จำนวน |
|---|---|---|---|---|
| `player_death` | เราตาย | ❌ เงียบ | death gasp, dying breath | 2 |
| `player_struggle` | ถูกซอมบี้จับ ดิ้นหลุด | ❌ เงียบ | struggle grunt, effort grunt | 3–4 |
| `drink_gulp` | ดื่มน้ำขวด น้ำเกลือ | 🔁 ใช้เสียงกิน | drinking gulp, swallow | 2–3 |
| `water_tap` | เปิดก๊อกเติมน้ำ | 🔁 ใช้เสียงกิน | faucet running, water pouring bottle | 2 |
| `water_splash` | ตักน้ำคลอง · ว่ายน้ำ · เดินลุยน้ำ | ❌ เงียบ | water splash, swimming splash | 3–4 |
| `bandage` | พันแผล · ใส่เฝือก | 🔁 ใช้เสียงกิน | bandage wrap, cloth tearing | 2 |
| `pills` | กินยาเม็ด | 🔁 ใช้เสียงกิน | pill bottle shake, blister pack | 2 |
| `jump_land` | กระโดดแล้วลงพื้น · ลงจากหลังคารถ | 🔁 ใช้เสียงเตะ | jump land thud, footstep land | 2–3 |
| `climb` | ปีนขึ้นหลังคารถ | 🔁 ใช้เสียงประตู | climbing metal, car roof climb | 2 |
| `step_metal` | เดินบนหลังคารถ สังกะสี | ❌ ใช้เสียงเดินปูน | footstep metal roof | 4–6 |
| `step_water` | เดินในน้ำตื้น | ❌ | footstep water puddle | 4–6 |
| `sleep_snore` | นอนหลับ (เบา ๆ) | ❌ เงียบ | snore soft, sleeping breathing | 1–2 |
| `cloth` | ใส่หรือถอดเสื้อผ้า | 🔁 ใช้เสียงค้นของ | clothes rustle, zipper | 2–3 |

## ชุดที่ 6: การต่อสู้ที่ยังขาด
| รหัส | ใช้ตอน | ตอนนี้ | คำค้น | จำนวน |
|---|---|---|---|---|
| `swing` | เหวี่ยงอาวุธ | 🤖 สร้างจากโค้ด | weapon swing whoosh, swoosh | 3–4 |
| `weapon_break` | อาวุธพัง | 🔁 ใช้เสียงกระดูกแตก | wood snap, metal break | 2 |
| `body_fall` | ซอมบี้ล้ม / ถูกเตะล้ม / ตาย | ❌ เงียบ (มีแค่เสียงโดน) | body fall thud, ragdoll fall | 3–4 |
| `stomp` | กระทืบซอมบี้ที่ล้ม | 🔁 ใช้เสียงเตะ | stomp crush, boot stomp | 2–3 |
| `throw` | ขว้างขวดหรือกระป๋อง | 🔁 ใช้เสียงต่อย | throw whoosh light | 2 |
| `silent_kill` | ฆ่าเงียบจากข้างหลัง | 🔁 ใช้เสียงมีด | muffled stab, neck stab | 2 |

## ชุดที่ 7: ของในเมือง
| รหัส | ใช้ตอน | ตอนนี้ | คำค้น | จำนวน |
|---|---|---|---|---|
| `shutter` | เปิดปิดประตูม้วนเหล็ก | 🤖 สร้างจากโค้ด | roller shutter, metal shutter door | 2 |
| `board_nail` | ตอกไม้ปิดประตูหน้าต่าง | 🔁 ใช้เสียงประตู | hammer nail wood, hammering | 3 |
| `car_alarm` | สัญญาณกันขโมยรถ | 🤖 สร้างจากโค้ด | car alarm | 1–2 |
| `car_bang` | ซอมบี้ทุบรถที่เรายืนบนหลังคา | 🔁 ใช้เสียงประตู | fist hitting car, banging metal | 3 |
| `stove` | เตาแก๊ส ต้มน้ำ หุงข้าว | 🔁 ใช้เสียงกิน | gas stove ignite, boiling water | 2 |
| `fridge_open` | เปิดตู้เย็น | ❌ ใช้เสียงค้นของ | fridge door open | 1–2 |
| `generator` | เครื่องปั่นไฟ ติด / ดัง (วนได้) / ดับ | 🔁 ใช้เสียงคลิก | generator start, generator running loop | 1 + 1 วน |
| `radio_static` | เปิดวิทยุ เสียงซ่า | 🔁 ใช้เสียงคลิก | radio static, radio tuning | 2 |
| `vending` | ทุบตู้กดน้ำ | ✅ แก้วแตก + หยิบของ | (มีพอ) | — |
| `fire_burn` | เผาศพ ไฟลุก (วนได้) | ❌ เงียบ | fire crackling loop | 1 วน |
| `trap` | เหยียบลวดหนาม / ตะปู | ❌ | barbed wire, metal spike step | 2 |
| `light_switch` | กดสวิตช์ไฟ (เมื่อมีไฟ) | ❌ | light switch click | 1–2 |

## ชุดที่ 8: รถ
| รหัส | ใช้ตอน | ตอนนี้ | คำค้น | จำนวน |
|---|---|---|---|---|
| `moto_start` | ต่อสายตรง สตาร์ตมอไซค์ | ❌ | motorcycle start, scooter start | 2 |
| `moto_engine` | เสียงเครื่องวิ่ง (วนได้ เกมปรับความเร็วเอง) | 🤖 สร้างจากโค้ด | scooter engine idle loop, motorcycle loop | 1–2 วน |
| `moto_horn` | บีบแตร (ยังไม่มีปุ่ม) | ❌ | scooter horn, motorcycle horn | 2 |
| `moto_brake` | เบรกไถล | ❌ | tire skid short | 2 |
| `crash` | ชนกำแพง | 🤖 สร้างจากโค้ด | motorcycle crash, metal crash | 2–3 |
| `fuel_pour` | เติมน้ำมัน | 🔁 ใช้เสียงค้นของ | pouring liquid, fuel pour | 1 |

## ชุดที่ 9: เพลงและหน้าจอ
| รหัส | ใช้ตอน | ตอนนี้ | คำค้น |
|---|---|---|---|
| `music_menu` | หน้าเมนูแรก | ❌ ใช้เพลงสำรวจ | post-apocalyptic ambient, dark menu music |
| `music_horde` | คืนฝูงบุก | 🔁 ใช้เพลงอันตราย | intense horror drums, survival horror action |
| `sting_death` | ตาย (ดนตรีสั้น ๆ) | ❌ | horror sting, death sting |
| `sting_dawn` | รอดคืนฝูงบุกมาได้ | ❌ | hopeful sting, sunrise ambient short |
| `ui_open` / `ui_close` | เปิดปิดกระเป๋า แผนที่ | ❌ | bag open, paper map unfold |
| `craft_done` | ทำของเสร็จ | 🔁 ใช้เสียงหยิบของ | crafting complete, tool clank |

**เครื่องหมาย "ตอนนี้":** ✅ มีเสียงของตัวเองแล้ว · 🔁 ยืมเสียงอื่นอยู่ (ใช้ได้ แต่ไม่ตรง) · 🤖 สร้างจากโค้ด (ฟังสังเคราะห์) · ❌ เงียบ
**มีครบแล้ว ไม่ต้องหา:** ต่อย เตะ โดนตี มีดฟันโดน กระดูกแตก เลือด ประตูเปิดปิด ประตูพัง กระจกแตก เดินบนปูน หญ้า ไม้ ·
ค้นของ หยิบของ กิน · ฝน ลม จิ้งหรีด หมาเห่า ครางไกล ๆ ข่าววิทยุ · เพลงสำรวจ กลางคืน อันตราย · ไซเรนฝูงบุก · เสียงคลิกเมนู

---
สถานะ: ✅ N = ใส่เข้าเกมแล้ว N แบบ (Claude อัปเดตทุกครั้งที่ใส่เสียงใหม่)

**มาตรฐานความดัง (Claude ใช้ตอนแปลง):** โมโน 44.1 kHz · ตัดช่วงเงียบหัวท้าย (−50 dB) · เสียงสั้น: ความดังเฉลี่ย ~−18 dB ·
เสียงยาว: −18 LUFS · ไม่เกิน −1.5 dBTP (ไม่แตก) · ogg vorbis q5
**ปรับแล้ว 2026-09-28:** เสียงครางเดิม groan_0–25 + snarl_0 เคยดังต่างกัน 33 dB (เฉลี่ย −9.7 ถึง −43 dB, 24 ไฟล์ชนเพดานจนแตก) → ปรับเป็นเฉลี่ย −18 dB ทุกไฟล์ (ต่างกัน < 1 dB) ไม่แตก
