;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Agent-Based Wildfire Simulation Environment (ABWISE)
;;;;; Author: Jeffrey Katan
;;;;; 17 June 2021

extensions [gis palette]

globals
[
  active-cells
  active-wind

  comparison-perimeter
  dynawind?

  hits
  misses
  false-alarms

  RoS-list
  avgRoS

  area
  BurnedArea

  max-density

  firetruck-created ;;Flag para saber si se ha creado un firetruck para click-Fire-truck

  t
  t30
]

breed [fires fire]
breed [fire-trucks fire-truck]
breed [vectors vector]

fires-own
[
  RoS
  cell
  collinear
  windmod

  density
  density-mod
]

fire-trucks-own
[
  truck-size  ;;Tamaño del firetruck
  fire-trucks-radius  ;;Radio de colisión con fuego
  fire-truck-collide ;;Flag para saber si un fire-truck entró en colisión con un fuego
  contador-ticks ;;Para contar ticks de reloj (para el delay apagando fuegos)
  apagando_fuego   ;;flag para saber cúando un agente de bomberos está apagando un fuego
]

patches-own
[
  fuel
  flam
  slope
  aspect
  windspe
  winddir
  globspe
  globdir

  fireX
  fireY

  windX
  windY

  globX
  globY

  fueltype
  water?
  nonfuel?

  wpatch?
  ignition?
  burned?
  perim?
  arrival-time

  pburned

]

to setup
  ca
  set dynawind? false
  set RoS-list []
  set firetruck-created false

  if scenario = 0  ; manual wind speed and direction input
    [
      set stoptime 1530 * rescale ; 25.5 hours between ignition ans start of firefighting
      set dynawind? true
      set wind-direction 55

      ;Cargar el mapa
      load-GIS-0
      landscape
      ask patches with [ignition?] [ignite]
    ]

  ;;if vectorshow? [vectorise] ; diagnostic

  reset-ticks
end


to load-GIS-0
  ;let vegetacion_galicia gis:load-dataset "DATA/MFE/MFE_11.shp"

  ;;Pilla las dimensiones del mapa
  ;gis:set-world-envelope gis:envelope-of vegetacion_galicia
  ;gis:set-drawing-color green

  ;Dibujo todos los elementos del fichero
  ;foreach gis:feature-list-of vegetacion_galicia [? -> gis:draw ? 1.0]


  let spec-rescale rescale
  let fueltypeData gis:load-dataset "DATA/MFE/modelo_combustible.asc"

  let new-world-width ((gis:width-of fueltypeData) * spec-rescale)
  let new-world-height ((gis:height-of fueltypeData) * spec-rescale)

  resize-world 0 (new-world-width - 1)  0 (new-world-height - 1)
  set-patch-size 900 / new-world-width                                      ; I should make the patch size change relative to the world size itself
  let envelope gis:envelope-of fueltypeData
  gis:set-world-envelope envelope

  gis:apply-raster fueltypeData fueltype


  print("Fueltype del patch 0 100 : ")
  show [fueltype] of patch 0 100  ; Imprime el area de un patch

  ask patches [
    set ignition? false set burned? false set perim? false set water? false set nonfuel? false
  ]
end

to ignite
      let directions [0 90 180 270]
      let i 0
      repeat 4
      [sprout-fires 1
        [
          set heading item i directions
          set size 0.8
          set cell list xcor ycor
          set color red
          fd 0.00001
          set RoS flam
        ]
        set i i + 1
      ]
end

to click-ignite
  if mouse-down?
  [ask patch mouse-xcor mouse-ycor
    [
      let directions [0 90 180 270]
      let i 0
      repeat 4
      [sprout-fires 1
        [
          set heading item i directions
          set size 0.5
          set cell list xcor ycor
          set color red
          fd 0.00001
          set RoS flam
        ]
        set i i + 1
      ]
    ]
    stop]
end

to click-firetruck

    ;;Inicia variable al soltar el botón del ratón
    if mouse-down? and (firetruck-created = false)
    [
    ;let new-fire-truck create-fire-truck 1 ; Crea un camión de bomberos
    create-fire-trucks 1[
      set fire-trucks-radius 2 ; Radio de extinción del incendio de camiones de bomberos
      set fire-truck-collide false
      set apagando_fuego false
      set truck-size 2
      set contador-ticks 0
      set size truck-size ; Tamaño de los camiones de bomberos
      set color yellow ; Asigna un color amarillo al camión de bomberos
      fd Firetrucks-speed
      setxy mouse-xcor mouse-ycor ; Establece la posición del camión de bomberos donde se hizo clic
    ]
    set firetruck-created true
  ]
  if not mouse-down? ;;Reinicia variable al soltar botón del ratón
  [
    set firetruck-created false
  ]
end

to go
  tick
  if not any? fires
  [
    set avgRoS mean RoS-list
    stop
  ]
  let RoS-at-tick mean [RoS] of fires
  set RoS-list lput RoS-at-tick RoS-list

  ;;if dynawind? [dynawind]
  wind-calc
  spread
  estrategia
  ;;check-and-extinguish-fires
  ask fire-trucks [
    if apagando_fuego = true [contar-ticks]
  ]

  consume

  ;;if vectorshow? [vectorshow] ; diagnostic
  ;;set BurnedArea (count patches with [burned?] * (2 * rescale) ^ 2 )


  ;ask patches [
    ; Verificar si el parche está quemado
    ;calcular area quemada (saber cuantas hectareas son un pixel y multiplicar por pixeles quemados)
  ;]
  ; Mostrar el área total quemada en la consola
  ;print (word "Área total quemada: " BurnedArea)

  if stoptime > 0
  [if ticks >= stoptime
    [
      set avgRoS mean RoS-list
      stop
    ]
  ]
end

to contar-ticks
      set contador-ticks contador-ticks + 1
end

to estrategia
    if Estrategy = "MIN_DISTANCE"[move-fire-trucks-nearest]
    if Estrategy = "MAX_DISTANCE"[move-fire-trucks-further]
    if Estrategy = "MAX_RoS"[move-fire-trucks-MaxRoS]
    if Estrategy = "MIN_RoS"[move-fire-trucks-MinRoS]
end

;;Visualizacion "FBPscheme": Depende del fueltype (nivel de fuel y flam)
;;Visualización "Terrain": depende de slope
;;Visualización "Flamability": Depende solo de la inflamabilidad (flam)
to landscape
  ask patches
  [
    (ifelse

      fueltype = 1 ; Pasto fino, seco y bajo. Pl leñosas < 1/3 de la superficie
      [
        set fuel 0.5
        set flam 0.85
        if Visualisation = "Fueltype" [set pcolor [50 100 50]] ;;
        ;set pcolor [51 59 71]
      ]
      fueltype = 2 ; Pasto fino, seco y bajo. Pl leñosas cubren  1/3 a 2/3 de la superficie
      [
        set fuel 0.5
        set flam 0.9
        if Visualisation = "Fueltype" [set pcolor [200 100 100]] ;;salmón
        ;set pcolor [65 80 87]
      ]
      fueltype = 3 ;Pasto denso, grueso, seco y alto (h>1m). Pl leñosas dispersas
      [
        set fuel 0.6
        set flam 0.5
        if Visualisation = "Fueltype" [set pcolor [255 255 0]] ;;Amarillo
        ;set pcolor [65 80 87]
      ]

      fueltype = 4 ; Matorral  denso y  verde (h>2 m). Propagación del fuego por las copas de las pl.
      [
        set fuel 0.4
        set flam 1.0
        if Visualisation = "Fueltype" [set pcolor [100 100 100]] ;;gris
        ;set pcolor [65 80 87]
      ]
      fueltype = 5 ; Matorral  denso y  verde (h<1 m). Propagación del fuego por la hojarasca y el pasto
      [
        set fuel 0.5
        set flam 0.9
        if Visualisation = "Fueltype" [set pcolor [50 70 0]] ;;Marrón Verdoso
        ;set pcolor [65 80 87]
      ]
      fueltype = 6 ; Parecido al modelo 5 pero con especies más inflamables o con restos de podasy pl de mayor talla
      [
        set fuel 0.5
        set flam 0.9
        if Visualisation = "Fueltype" [set pcolor [170 100 0]] ;;Naranja
        ;set pcolor [79 101 104]
      ]
      fueltype = 7 ;Matorral de especies muy inflamables (h: 0,5-2 m) situado como sotobosque de masas de coníferas
      [
        set fuel 0.3
        set flam 0.9
        if Visualisation = "Fueltype" [set pcolor [120 50 100]] ;; Rosa
        ;set pcolor [95 120 117]
      ]
      fueltype = 8 ;Bosque denso, sin matorral. Propagación del fuego por hojarasca muy compacta
      [
        set fuel 0.5
        set flam 0.2
        if Visualisation = "Fueltype" [set pcolor [30 100 20]] ;;Verde
        ;set pcolor [95 120 117]
      ]
      fueltype = 9 ;Parecido al modelo 8 pero con hojarasca menos compacta formada por acículas largas y rígidas o follaje de frondosas de hojas grandes
      [
        set fuel 0.5
        set flam 0.2
        if Visualisation = "Fueltype" [set pcolor [180 235 20]] ;;Amarillo verdoso
        ;set pcolor [95 120 117]
      ]
      fueltype = 10 ;Bosque con gran cantidad de leña y árboles caídos, como consecuencia de vendavales, plagas intensas, etc.
      [
        set fuel 0.5
        set flam 0.2
        if Visualisation = "Fueltype" [set pcolor [30 235 65]] ;;Verde clarito
        ;set pcolor [95 120 117]
      ]

      fueltype = 11 ;Bosque claro y fuertemente aclarado. Restos de poda o aclarado dispersos con pl herbáceas rebrotando
      [
        set fuel 0.5
        set flam 0.2
        if Visualisation = "Fueltype" [set pcolor [30 235 110]] ;; Verde azulado
        ;set pcolor [95 120 117]
      ]
      fueltype = 12 ;Predominio de los restos sobre el arbolado. Restos de poda o aclareo cubriendo todo el suelo
      [
        set fuel 0.5
        set flam 0.2
        if Visualisation = "Fueltype" [set pcolor [100 100 0]] ;;Ocre
        ;set pcolor [95 120 117]
      ]

      fueltype = 13 ;Grandes acumulaciones de restos gruesos y pesados, cubriendo todo el suelo.
      [
        set fuel 0.5
        set flam 0.2
        if Visualisation = "Fueltype" [set pcolor [100 0 100]] ;;Violeta
        ;set pcolor [95 120 117]
      ]
      [
        ;;En caso de no ser ninguno de estos tipos:
        set fuel 0.5
        set flam 0.5
        if Visualisation = "Fueltype" [set pcolor [255 255 255] ] ;;Blanco
        ;set pcolor [38 41 54]
      ]
    )
    set flam flam-level set fuel fuel-level
    ;if Visualisation = "Flammability" [
    ;ifelse not water? and not nonfuel? [
    ;set pcolor palette:scale-gradient [[144 170 149][111 137 127][95 120 117][65 80 87][51 59 71][38 41 54]] flam 0 1]
    ;[if water? [set pcolor [139 163 189]] if nonfuel? [set pcolor [188 188 181]]]]
  ]
end

;;Calculos del viento
to wind-calc
  let spec-rescale rescale
  if rescale > 1 [set spec-rescale rescale ^ 0.25]
  set active-cells patches with [any? fires-here or any? fires in-radius (4 * spec-rescale)] ; size of this is a parameter I haven't even touched
  set active-wind patches with [any? fires in-radius (6 * spec-rescale )]
  let w1 0.44
  let w2 0.24

  ask active-wind
  [
    ifelse scenario = 3 or scenario = 4
    [
      ifelse wpatch?
      [
        set globX sin(100) * wind-speed / 60
        set globY cos(100) * wind-speed / 60
      ]
      [
        set globX sin(wind-direction) * wind-speed / 60
        set globY cos(wind-direction) * wind-speed / 60
      ]
    ]
    [
      set globX sin(wind-direction) * wind-speed / 60
      set globY cos(wind-direction) * wind-speed / 60
    ]
    set windX w1 * globX + (1 - w1) * (w2 * windX + (1 - w2) * fireX)
    set windY w1 * globY + (1 - w1) * (w2 * windY + (1 - w2) * fireY)
  ]

  ask active-cells
  [ ; make wind vector a mix of the fire vector and the global wind
    fIDW fires in-radius 1
    if any? fires-here [fSlope-Aspect]
    wIDW active-wind
  ]

  ask active-wind
  [
    ifelse windX = 0 or windY = 0
    [
      set winddir atan globX globY
      set windspe ((globX ^ 2) + (globY ^ 2)) ^ 0.5
    ]
    [
      set winddir atan windX windY
      set windspe ((windX ^ 2) + (windY ^ 2)) ^ 0.5
    ]
  ]

 ; ask active-cells [set pcolor yellow]

end

to wIDW [#set]
  let surround other #set
  let sumsin       sum [windX / (distance myself ^ 2)] of surround
  let sumcos       sum [windY / (distance myself ^ 2)] of surround
  let denominator  sum [1 / (distance myself ^ 2)] of surround
  ifelse denominator != 0
  [

    ; The x and y components of the interpolated RoS vector
    set windX (sumsin / denominator)
    set windY (sumcos / denominator)
  ]
  []
end

to fIDW [#set]

  let sumsin       sum [sin(heading) * RoS / (distance myself ^ 2)] of #set
  let sumcos       sum [cos(heading) * RoS / (distance myself ^ 2)] of #set
  let denominator  sum [1 / (distance myself ^ 2)] of #set
  ifelse denominator != 0
  [
    ; The x and y components of the interpolated RoS vector
    set fireX (sumsin / denominator)
    set fireY (sumcos / denominator)
  ]
  []
end

to fSlope-Aspect
  let p1 0 ifelse any? fires-at -1 1 [set p1 sum [RoS] of fires-at -1 1][set p1 sum [RoS] of fires-here]
  let p2 0 ifelse any? fires-at 0 1 [set p2 sum [RoS] of fires-at 0 1][set p2 sum [RoS] of fires-here]
  let p3 0 ifelse any? fires-at 1 1 [set p3 sum [RoS] of fires-at 1 1][set p3 sum [RoS] of fires-here]
  let p4 0 ifelse any? fires-at -1 0 [set p4 sum [RoS] of fires-at -1 0][set p4 sum [RoS] of fires-here]
  let p6 0 ifelse any? fires-at 1 0 [set p6 sum [RoS] of fires-at 1 0][set p6 sum [RoS] of fires-here]
  let p7 0 ifelse any? fires-at -1 -1 [set p7 sum [RoS] of fires-at -1 -1][set p7 sum [RoS] of fires-here]
  let p8 0 ifelse any? fires-at 0 -1 [set p8 sum [RoS] of fires-at 0 -1][set p8 sum [RoS] of fires-here]
  let p9 0 ifelse any? fires-at 1 -1 [set p9 sum [RoS] of fires-at 1 -1][set p9 sum [RoS] of fires-here]

  let x-slope ((p3 + 2 * p6 + p9) - (p1 + 2 * p4 + p7)) / 8
  let y-slope ((p1 + 2 * p2 + p3) - (p7 + 2 * p8 + p9)) / 8

  set fireX 3 * x-slope + fireX
  set fireY 3 * y-slope + fireY
end


;;Estrategia de camiones de bomberos para dirgirse al más cercano
to move-fire-trucks-nearest
    ask fire-trucks [
      let nearest-fire min-one-of fires [distance myself]
      if any? fires[
        face nearest-fire
        apagar_fuego
        check-and-extinguish-fires
      ]if not any? fires [
      print "No hay fuegos por apagar."
      ]
    ]
end

to move-fire-trucks-further
    ask fire-trucks [
      let further-fire max-one-of fires [distance myself]
      if any? fires[
        face further-fire
        apagar_fuego
        check-and-extinguish-fires
      ]if not any? fires [
        print "No hay fuegos por apagar."
      ]
    ]
end

;;Estrategia de camiones de bomberos para dirigirse a fuego de mayor RoS
to move-fire-trucks-MaxRoS

    ask fire-trucks [
      let max_RoS max-one-of fires [RoS]
      if any? fires[
        face max_RoS
        apagar_fuego
        check-and-extinguish-fires
      ] if not any? fires [
        print "No hay fuegos por apagar."
      ]
  ]
end

;; Estrategia de camiones de bomberos para dirigirse a fuego de menor RoS
to move-fire-trucks-MinRoS

    ask fire-trucks [
      let min_RoS min-one-of fires [RoS]
      if any? fires [
        face min_RoS
        check-and-extinguish-fires
        apagar_fuego
      ]if not any? fires [
        print "No hay fuegos por apagar."
      ]
    ]
end

;; Comprueba si hay un fuego en un radio determinado y lo elimina
to check-and-extinguish-fires
  let fires-in-radius fires in-radius fire-trucks-radius

  ifelse any? fires-in-radius [
    set fire-truck-collide true
    set apagando_fuego true

    let target-fire one-of fires-in-radius
    ask target-fire [
      set color green
      die
    ]
  ] [
    ; No hay fuego en el vecindario
  ]
end

to apagar_fuego
  if (apagando_fuego = true) and  (fire-truck-collide = true) [
    fd 0
    set color orange
  ]

  ; Si no se está apagando el fuego
  if (contador-ticks > Delay) or (contador-ticks = 0) [
    set apagando_fuego false
    fd Firetrucks-speed  ; Velocidad del camión de bomberos en casillas por tick de reloj (desde la interfaz)
    set contador-ticks 0
    set color yellow
  ]
end

;;Calculos para la propagación del fuego
to spread
  set max-density max [density] of fires
  let f1 0.20
  let f2 0.81
  let d1 2.5
  let s1 0.019
  let w3 4.2
  let m1 0.2
  let a 0.57
  let b 180
  let k 16

  ask fires
  [
    ;set collinear windspe * cos(subtract-headings heading winddir)
    set collinear cos(subtract-headings heading winddir)
    let coslope cos(subtract-headings heading (aspect - 180))
    let RoSx RoS * sin(heading)
    let RoSy RoS * cos(heading)


 ;;;;;;;;;;;; The main RoS calculations
    let surround fires in-radius 1
    set density count surround
    let near-density mean [density] of surround

    let scale-density  ((density + 1) / (max-density + 1))
    let scale-near-density ((near-density + 1) / (max-density + 1))

    set density-mod scale-density - scale-near-density

    set windmod  (a + flam / 30) / ((1 + (b) * e ^ (- (k) * windspe)) ^ (1 / (flam + (2.6 + RoS)) ))
    set RoS ((f1 * RoS  + (1 - f1) * (((flam) ^ 1.3) + flam + w3 * windspe * abs(collinear)) + s1 * slope / 100 * coslope)) * (m1 * windmod)

    let f2-2 f2 * (1.2 - windmod / 1.3)
    let Cx ((RoS * sin(heading)) * (f2-2) * (1 + density-mod * d1) + windX * (1.05 - f2-2) * windmod + (s1 * slope / 100 * sin(aspect - 180)))
    let Cy ((RoS * cos(heading)) * (f2-2) * (1 + density-mod * d1) + windY * (1.05 - f2-2) * windmod + (s1 * slope / 100 * cos(aspect - 180)))
    ;print("SLOPE: ")
    ;print(slope)
    ;;print("Aspect: ")
    ;;print(aspect)
 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


 ;;;;;;;;;;;; This recombines components into magnitude and direction for the fire agents
    let Cmag ((Cx ^ 2) + (Cy ^ 2)) ^ 0.5
    let Cang atan Cx Cy
    set heading Cang
    set RoS Cmag
    let spotting? true
    ;;; spotting (desplazamiento del fuego, como cuando los conejos saltan de una posición a otra)
    ifelse spotting? [
      let p-spot 0.005 * windspe * RoS
      ifelse p-spot > random-float 1
      [fd RoS * (2 * random (2 + windspe * 4)) ask patch-here [ignite]]
      [fd RoS]
    ]
    [fd RoS]
 ;;;;;;;;;;;;;;;;;;;;;

    set color scale-color red RoS -0.2 0.8
    ifelse ticks mod 30 = 0
    [stamp]
    []
    ;; stamp? [stamp]
 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

 ;; Para que se eliminen los fuegos que salen de los extremos de la pantalla


 ;;;;;;;;;;;; Pre-heating
 ;;Si no hay patch-ahead quiere decir que se encuentra en un extremo del mapa y por lo tanto el siguiete patch no existe, entonces muere
    if (patch-ahead 1 != nobody) [
      ask patch-ahead 1 [
        if flam < 1 [
          set flam flam + (0.005 * [RoS] of myself) / (1 + distance myself) ^ 2
        ]
      ]
    ] if (patch-ahead 1 = nobody) [
      die
    ]
     check-cell
    ]
end

;;Comprobación de si la casilla es diferente al principio y si hay suficiente fuel
to check-cell
  ; Checks if the cell is different from origin cell and if there is enough fuel
  ask fires
  [
    if fuel <= 0.2 * (1.1 - RoS * rescale)
    [
      if random-float (1 - RoS / 10) < RoS
      [die]
    ]
    if distancexy item 0 cell item 1 cell > (4 * RoS) ^ 0.5 and count fires-here < 3 ; if this agent has travelled more than (4 * its RoS(current))^0.5, and there are fewer than 3 other fires
    [
      propagate
      die
    ]
    if RoS <= 0 [die]
  ]
end

;;Función de propagación del fuego (como cuando los conejos se reproducen en el modelo de comportamiento de conejos)
to propagate
  ; Creates new fires when fire agents enter a new cell
  let mycolor color
  let directions [0 -45 45]
  foreach directions
  [i ->
    hatch-fires 1
    [
      set heading heading + i
      set cell list xcor ycor
      set color mycolor
    ]
  ]
end

;;función de consumición del fuel (como cuando los conejos comen en el modelo de comportamiento de conejos (necesitan comer para seguir vivos))
to consume
  let burnscaler 17

  ask fires
  [
    set fuel fuel - ((RoS) * fuel / burnscaler)
    ;set fuel fuel - RoS * 0.5 / burnscaler
  ]
  ask patches with [any? fires-here] ;this is probably a source of slow-down
  [
    set burned? true
    set pcolor scale-color blue fuel 0 1
    if arrival-time <= 0
    [set arrival-time ticks]
  ]
end

;;Para exportar la screenshot del escenario del modelo en la carpeta Raster_out
to exportscarauto
  ; For use in automated experiments
  ; to output a raster after each model run.
  ; First one is just the scar

  ask patches [
    ifelse burned? = true
    [set pburned 1]
    []]
  let burnscar gis:patch-dataset pburned
  let counter 94
  gis:store-dataset burnscar (word "Raster_out/" folder-name "/V23_" counter "_scen_" scenario "_scale_" rescale "_"  ".asc")

  ; Second is FoM
  ask patches
  [(ifelse
    burned? = true and perim? = true ;hits
    [set pburned 1000000]
    burned? = false and perim? = true ; misses
    [set pburned 1000]
    burned? = true and perim? = false ; false-alarms
    [set pburned 1]

    [set pburned 0]
  )
  ]
  let burnscarfom gis:patch-dataset pburned
  gis:store-dataset burnscarfom (word "Raster_out/" folder-name "/V23_fom_" counter "_scen_" scenario "_scale_" rescale "_"  ".asc")

  ;Third is arrival time
  let arrivaltime gis:patch-dataset arrival-time
  gis:store-dataset arrivaltime (word "Raster_out/" folder-name "/AT_" counter "_scen_" scenario "_scale_" rescale "_"  ".asc")

end

to vectorise
  ask patches [
    sprout-vectors 1
    [set color white
      set shape "line half"
      set size 0.4
      set heading [winddir] of patch-here]]
end


to-report performance
  set t t + 1
  every 1
  [set t30 t
    set t 0]
  report t30
end

;Copyright 2021 Jeffrey Katan
@#$#@#$#@
GRAPHICS-WINDOW
449
10
1356
580
-1
-1
2.5210084033613445
1
10
1
1
1
0
0
0
1
0
356
0
222
0
0
1
ticks
30.0

BUTTON
6
10
179
43
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
7
137
179
170
wind-speed
wind-speed
0.01
50
13.01
1
1
NIL
HORIZONTAL

INPUTBOX
5
317
60
395
stoptime
1530.0
1
0
Number

SLIDER
7
171
179
204
wind-direction
wind-direction
0
360
55.0
5
1
NIL
HORIZONTAL

BUTTON
98
43
179
88
go
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
7
266
79
311
NIL
count fires
17
1
11

MONITOR
79
266
179
311
NIL
count active-cells
17
1
11

MONITOR
3
464
87
509
RoS in Cell/Tick
mean [RoS] of fires
4
1
11

SLIDER
7
234
179
267
fuel-level
fuel-level
0
1
0.5
0.1
1
NIL
HORIZONTAL

SLIDER
7
203
179
236
flam-level
flam-level
0
1
0.5
0.1
1
NIL
HORIZONTAL

CHOOSER
6
43
98
88
scenario
scenario
0
0

MONITOR
283
464
447
509
avg RoS start to finish (m/min)
avgRoS * 200
4
1
11

MONITOR
160
464
283
509
Area Quemada (ha)
BurnedArea
0
1
11

INPUTBOX
60
317
111
395
rescale
1.0
1
0
Number

MONITOR
87
464
161
509
RoS in m/min
mean [RoS] of fires * 200
4
1
11

CHOOSER
210
64
336
109
Visualisation
Visualisation
"Fueltype" "Flamability"
0

BUTTON
94
95
175
128
NIL
click-ignite
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

INPUTBOX
204
342
397
402
folder-name
Tijuana
1
0
String

BUTTON
204
402
397
435
Export interface image
export-interface (word \"Raster_out/\" folder-name \"/Interface.png\")
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

TEXTBOX
207
317
394
361
Name of folder where Monte Carlo simulation results will be stored.
9
0.0
1

BUTTON
10
95
96
128
show-grid
ask patches [\nsprout 1\n[set shape \"square\"\nset size 1.2\nset color pcolor\n]\nset pcolor white\n]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
212
12
272
57
ticks/sec
performance
4
1
11

TEXTBOX
209
135
359
153
FIRETRUCKS
10
0.0
1

SLIDER
206
236
378
269
Firetrucks-speed
Firetrucks-speed
0
1
0.5
0.1
1
NIL
HORIZONTAL

BUTTON
207
151
310
184
Click-firetruck
click-firetruck
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

CHOOSER
206
190
371
235
Estrategy
Estrategy
"MIN_DISTANCE" "MAX_DISTANCE" "MAX_RoS" "MIN_RoS"
0

SLIDER
207
271
379
304
Delay
Delay
0
10
5.0
1
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

ABWiSE translates the concept of a moving fire front as a set of mobile fire agents that, viewed in aggregate, form a line of varying thickness. Ultimately, the goal of such a fire simulation model is to predict fire behaviour, but presently, the purpose of ABWiSE is to explore how ABM, using simple interactions between agents and a simple atmospheric feedback model, can simulate emerging fire spread patterns.

## HOW IT WORKS

Fire is represented by agents that follow rules accounting for vegetation, terrain, and wind, and the interactions among the agents and with their environment, (such as fire-atmosphere feedback).

A model run begins with an ignition, creating four fire agents at that point, each facing one cardinal direction. Since flammability is the first driver of fire spread, fire agents have an initial RoS value set to the flammability of the cell they start in. At each time step, fire-atmosphere interactions provide a local effective wind speed and direction for cells within a certain distance of fire agents. Next, fire agents update their RoS and heading based on wind, flammability, terrain, and the local density of fire agents, and then move by that RoS in that direction. After moving, agents preheat the cell within the distance of their RoS by a small amount, raising its flammability . Next, agents have a chance to be extinguished (or die) based on the fuel value at their location and their RoS. Those that do not die then propagate if they have travelled more than a certain distance from their point of origin and if there are fewer than a set number of other fires already in their current cell. Lastly, fire agents reduce the amount of fuel in a cell based on their RoS. Simulation ends if there are no more fire agents, or after a predetermined number of iterations.

## HOW TO USE IT

Choose a scenario, click setup, and then go.
Scenario 0 lets the user choose their own stoptime, wind speed, and wind direction. All other scenarios have preset values for those variables, though they can be changed after setup.

The user may also choose among different visualizations for scenarios 3, 4, 5, and 6
Scenario 6 is a multiday fire for which the model does not have correct weather data. It was left in to show how a larger fire might be simulated.

Because the model is not deterministic, meaningful results require Monte Carlo simulation. Using the Behaviourspace tool, users may create and run experiments that can run the model repeatedly and either maintain or change variables. The experiment named "MonteCristo" will run scenarios 1, 2, 4, and 5, at two different resolutions, 100 times each, and export a raster of each run. They will be found in the folder designated by the user in the interface tab. The ensuing 600 maps can be processed in your GIS of choice. (Consider using R, as well).


## THINGS TO TRY

Play around with the parameters, especially when running scenario 1 or scenario 2, to see the effect of each and notice the model's sensitivity to various parameters.

## EXTENDING THE MODEL

Try testing the model against new fire scenarios. The model requires ASCII raster files for slope, aspect, and fuel type, as well as an ignition source in the form of a point shapefile. (Lines and polygons are supported by the GIS extension, but the ignition procedure in the model will need to be adapted to handle them).

Any dynamic weather data must be hard-coded in the "dynawind" procedure.

Or you could create a procedure to read weather data from a table.


## CREDITS AND REFERENCES

Copyright 2021 Jeffrey Katan
This work is licensed under the Creative Commons Attibution 4.0 International license.
More information can be found here https://creativecommons.org/licenses/by/4.0/
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
4
Polygon -7500403 true false 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true false 47 195 58
Circle -7500403 true false 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="test_experiment" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="121"/>
    <metric>fom-stats</metric>
    <enumeratedValueSet variable="scenario">
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <steppedValueSet variable="w2" first="0" step="0.2" last="1"/>
    <steppedValueSet variable="w1" first="0" step="0.2" last="1"/>
    <steppedValueSet variable="f2" first="0" step="0.2" last="1"/>
    <enumeratedValueSet variable="f1">
      <value value="0.5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="stoptime">
      <value value="120"/>
    </enumeratedValueSet>
    <steppedValueSet variable="burnscaler" first="1" step="3" last="15"/>
  </experiment>
  <experiment name="parameter_sweep_1" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="122"/>
    <metric>fom-stats</metric>
    <enumeratedValueSet variable="scenario">
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <steppedValueSet variable="w1" first="0.2" step="0.3" last="0.8"/>
    <steppedValueSet variable="w2" first="0.2" step="0.3" last="0.8"/>
    <enumeratedValueSet variable="w3">
      <value value="4"/>
      <value value="5"/>
      <value value="6"/>
    </enumeratedValueSet>
    <steppedValueSet variable="f1" first="0.1" step="0.3" last="0.9"/>
    <steppedValueSet variable="f2" first="0.1" step="0.3" last="0.9"/>
    <enumeratedValueSet variable="a">
      <value value="1"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="b">
      <value value="20"/>
      <value value="30"/>
      <value value="40"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="k">
      <value value="20"/>
      <value value="30"/>
      <value value="40"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="m1">
      <value value="0.09"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="burnscaler">
      <value value="10"/>
      <value value="15"/>
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="d1">
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="counter">
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Logistic_variation1" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="122"/>
    <metric>fom-stats</metric>
    <metric>avgRoS</metric>
    <metric>area</metric>
    <steppedValueSet variable="m1" first="0.06" step="0.006" last="0.12"/>
    <steppedValueSet variable="a" first="0.8" step="0.08" last="1.2"/>
    <steppedValueSet variable="b" first="30" step="8" last="70"/>
    <steppedValueSet variable="k" first="10" step="6" last="40"/>
    <steppedValueSet variable="w3" first="4" step="0.5" last="7"/>
    <enumeratedValueSet variable="scenario">
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="Logistic_stochastic" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="122"/>
    <metric>fom-stats</metric>
    <metric>avgRoS</metric>
    <metric>area</metric>
    <steppedValueSet variable="m1" first="0.08" step="0.002" last="0.11"/>
    <steppedValueSet variable="a" first="0.9" step="0.05" last="1.1"/>
    <steppedValueSet variable="b" first="30" step="2" last="40"/>
    <steppedValueSet variable="k" first="25" step="2" last="35"/>
    <steppedValueSet variable="w3" first="4" step="0.2" last="6"/>
    <enumeratedValueSet variable="scenario">
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="counter">
      <value value="0"/>
      <value value="1"/>
      <value value="2"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="refined_sweep_1" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="122"/>
    <metric>fom-stats</metric>
    <enumeratedValueSet variable="scenario">
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
    </enumeratedValueSet>
    <steppedValueSet variable="f1" first="0.1" step="0.02" last="0.2"/>
    <steppedValueSet variable="f2" first="0.75" step="0.02" last="0.85"/>
    <steppedValueSet variable="w1" first="0.2" step="0.1" last="0.8"/>
    <steppedValueSet variable="w2" first="0.2" step="0.1" last="0.8"/>
    <steppedValueSet variable="w3" first="3" step="0.3" last="7"/>
    <steppedValueSet variable="m1" first="0.07" step="0.02" last="0.12"/>
  </experiment>
  <experiment name="experiment" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <postRun>exportscarauto</postRun>
    <steppedValueSet variable="counter" first="0" step="1" last="10"/>
  </experiment>
  <experiment name="bigsteps_all_scen4_lowres" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="203"/>
    <metric>fom-stats</metric>
    <enumeratedValueSet variable="w1">
      <value value="0.3"/>
      <value value="0.5"/>
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w2">
      <value value="0.3"/>
      <value value="0.5"/>
      <value value="0.8"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w3">
      <value value="2"/>
      <value value="5"/>
      <value value="7"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="d1">
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="f1">
      <value value="0.1"/>
      <value value="0.2"/>
      <value value="0.4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="f2">
      <value value="0.5"/>
      <value value="0.7"/>
      <value value="0.9"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="b">
      <value value="30"/>
      <value value="70"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="k">
      <value value="25"/>
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="m1">
      <value value="0.09"/>
      <value value="0.1"/>
      <value value="0.11"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="burnscaler">
      <value value="15"/>
      <value value="25"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="counter">
      <value value="0"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="fine_tune_sto" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="404"/>
    <metric>fom-stats</metric>
    <enumeratedValueSet variable="counter">
      <value value="1"/>
      <value value="2"/>
      <value value="3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w1">
      <value value="0.35"/>
      <value value="0.375"/>
      <value value="0.4"/>
      <value value="0.44"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="w2">
      <value value="0.1"/>
      <value value="0.15"/>
      <value value="0.2"/>
      <value value="0.25"/>
      <value value="0.3"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="f1">
      <value value="0.15"/>
      <value value="0.175"/>
      <value value="0.2"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="f2">
      <value value="0.7"/>
      <value value="0.75"/>
      <value value="0.78"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="a">
      <value value="0.5"/>
      <value value="0.54"/>
      <value value="0.56"/>
      <value value="0.6"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="burnscaler">
      <value value="11"/>
      <value value="13"/>
      <value value="15"/>
      <value value="17"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="MonteCarlo" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <postRun>exportscarauto</postRun>
    <timeLimit steps="404"/>
    <metric>fom-stats</metric>
    <steppedValueSet variable="counter" first="1" step="1" last="100"/>
    <enumeratedValueSet variable="scenario">
      <value value="1"/>
      <value value="2"/>
      <value value="4"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rescale">
      <value value="1"/>
      <value value="0.4"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="MonteCarlo_val" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <postRun>exportscarauto</postRun>
    <timeLimit steps="1530"/>
    <metric>fom-stats</metric>
    <steppedValueSet variable="counter" first="1" step="1" last="100"/>
    <enumeratedValueSet variable="scenario">
      <value value="5"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="rescale">
      <value value="1"/>
      <value value="0.4"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="performance" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>t30</metric>
    <metric>count fires</metric>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
