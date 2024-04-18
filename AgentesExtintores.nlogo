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

  (ifelse
    scenario = 0  ; manual wind speed and direction input
    [
      resize-world 0 57 * rescale 0 38 * rescale
      set-patch-size 900 / world-width
      set stoptime 121 * rescale
      ask patches [set ignition? false set burned? false set perim? false set water? false set nonfuel? false] ; this patch initialisation must be redone in GIS procedures when changing scale
      landscape ask patch (max-pxcor / 2) (max-pycor / 2) [set ignition? true]
      ask patches with [ignition?] [ignite]
    ]

    scenario = 1  ; 1km wind speed
    [

      set stoptime 121 * rescale
      set wind-speed 1
      set wind-direction 270
      load-GIS-1-2
      landscape ;landscape procedure has to happen before ignition
      ask patches with [ignition?] [ignite]
    ]
    scenario = 2
    [

      set stoptime 121 * rescale
      set wind-speed 20
      set wind-direction 270
      load-GIS-1-2
      landscape ;landscape procedure has to happen before ignition
      ask patches with [ignition?] [ignite]
    ]

    scenario = 3 or scenario = 4 ; 3 and 4 are the same scenarios but with different comparison perimeters
    [ ; 3 is the perimeter as simulated by Prometheus, and 4 is the actual Dogrib fire perimeter

      set stoptime 403 * rescale ; 6h42m + 1  ; and what about rescale??
      set dynawind? true
      set wind-direction 55
      load-GIS-3-4
      landscape
      ask patches with [ignition?] [ignite]
    ]
    scenario = 5; 5 is the first, and smaller part of the Dogrib fire
    [

      set stoptime 1530 * rescale ; 25.5 hours between ignition ans start of firefighting
      set dynawind? true
      set wind-direction 55

      ;Cargar el mapa
      load-GIS-5
      landscape
      ask patches with [ignition?] [ignite]
    ]

    scenario = 6; 6 is a validation fire test based on Global Fire Atlas data
    [

      set stoptime 30240 * rescale ; 21 days seems a bit long.....
      set dynawind? false
      set wind-direction 55
      load-GIS-6
      landscape-validation
      ask patches with [ignition?] [ignite]
    ]
    []
  )

  if vectorshow? [vectorise] ; diagnostic

  reset-ticks
end

to load-GIS-1-2

  let fueltypeData gis:load-dataset "Data/fbp_uni_spruce.asc"

  let new-world-width ((gis:width-of fueltypeData) * rescale)
  let new-world-height ((gis:height-of fueltypeData) * rescale)

  resize-world 0 (new-world-width - 1)  0 (new-world-height - 1)
  set-patch-size 900 / new-world-width
  let envelope gis:envelope-of fueltypeData
  gis:set-world-envelope envelope

  ask patches
  [
    set ignition? false set burned? false set perim? false set water? false set nonfuel? false
    set slope 0 set aspect 0
  ] ; Patch init must happen right after resize

  gis:apply-raster fueltypeData fueltype
  ask patches
  [
    ifelse (fueltype <= 0) or (fueltype >= 0)
    []
    [set fueltype -9999]
  ]

  let ignitionData gis:load-dataset "Data/Cent_pt_ignit.shp"
  ask patches gis:intersecting ignitionData
  [set ignition? true]

  if scenario = 1
  [set comparison-perimeter gis:load-dataset "Data/Scenario1_25C_1km.shp"]
  if scenario = 2
  [set comparison-perimeter gis:load-dataset "Data/Scenario2_25C_20km.shp"]

  ask patches gis:intersecting comparison-perimeter [set perim? true]

end

to load-GIS-3-4

  let spec-rescale rescale / 2
  let fueltypeData gis:load-dataset "Data/fueltype.asc"

  let new-world-width ((gis:width-of fueltypeData) * spec-rescale)
  let new-world-height ((gis:height-of fueltypeData) * spec-rescale)

  resize-world 0 (new-world-width - 1)  0 (new-world-height - 1)
  set-patch-size 900 / new-world-width                                      ; I should make the patch size change relative to the world size itself
  let envelope gis:envelope-of fueltypeData
  gis:set-world-envelope envelope

  ask patches
  [
    set ignition? false set burned? false set perim? false set water? false set nonfuel? false
  ] ; Patch init must happen right after resize

  gis:apply-raster fueltypeData fueltype
  ask patches
  [
    ifelse (fueltype <= 0) or (fueltype >= 0)
    []
    [set fueltype -9999]
  ]

  let slopeData gis:load-dataset "Data/slopeperc1.asc"
  gis:apply-raster slopeData slope
  ask patches
  [
  ifelse (slope <= 0) or (slope >= 0)
    []
    [set slope -9999]
  ]
  let aspectData gis:load-dataset "Data/aspect1.asc"
  gis:apply-raster aspectData aspect
  ask patches
  [
  ifelse (aspect <= 0) or (aspect >= 0)
    []
    [set aspect -9999]
  ]

  let weatherpatch gis:load-dataset "Data/wpatch2.shp"
  ask patches [set wpatch? false]
  ask patches gis:intersecting weatherpatch [set wpatch? true]

  let ignitionData gis:load-dataset "Data/ignitPoint.shp"
  ask patches gis:intersecting ignitionData
  [set ignition? true]

  if scenario = 3
  [set comparison-perimeter gis:load-dataset "Data/test1perim.shp"]
  if scenario = 4
  [set comparison-perimeter gis:load-dataset "Data/DogribRun2.shp"]

  ask patches gis:intersecting comparison-perimeter [set perim? true]

end

to load-GIS-5
  let spec-rescale rescale / 2
  let fueltypeData gis:load-dataset "Data/fueltype.asc"

  let new-world-width ((gis:width-of fueltypeData) * spec-rescale)
  let new-world-height ((gis:height-of fueltypeData) * spec-rescale)

  resize-world 0 (new-world-width - 1)  0 (new-world-height - 1)
  set-patch-size 900 / new-world-width                                      ; I should make the patch size change relative to the world size itself
  let envelope gis:envelope-of fueltypeData
  gis:set-world-envelope envelope

  ask patches
  [
    set ignition? false set burned? false set perim? false set water? false set nonfuel? false
  ] ; Patch init must happen right after resize

  gis:apply-raster fueltypeData fueltype
  ask patches
  [
    ifelse (fueltype <= 0) or (fueltype >= 0)
    []
    [set fueltype -9999]
  ]

  let slopeData gis:load-dataset "Data/slopeperc1.asc"
  gis:apply-raster slopeData slope
  ask patches
  [
  ifelse (slope <= 0) or (slope >= 0)
    []
    [set slope -9999]
  ]
  let aspectData gis:load-dataset "Data/aspect1.asc"
  gis:apply-raster aspectData aspect
  ask patches
  [
  ifelse (aspect <= 0) or (aspect >= 0)
    []
    [set aspect -9999]
  ]

  let ignitionData gis:load-dataset "Data/ignit_sep_29.shp"
  ask patches gis:intersecting ignitionData
  [set ignition? true]

  set comparison-perimeter gis:load-dataset "Data/Sep_30_perim.shp"
  ask patches gis:intersecting comparison-perimeter [set perim? true]

end

to load-GIS-6 ; trying a validation fire

  let spec-rescale rescale ;/ 2 ; base input should be 200m resolution
  let fueltypeData gis:load-dataset "Data/Validationagain_2012/fbp1.asc"

  let new-world-width ((gis:width-of fueltypeData) * spec-rescale)
  let new-world-height ((gis:height-of fueltypeData) * spec-rescale)

  resize-world 0 (new-world-width - 1)  0 (new-world-height - 1)
  set-patch-size 900 / new-world-width                                      ; I should make the patch size change relative to the world size itself
  let envelope gis:envelope-of fueltypeData
  gis:set-world-envelope envelope

  ask patches ;initialize
  [
    set ignition? false set burned? false set perim? false set water? false set nonfuel? false
  ] ; Patch init must happen right after resize

  gis:apply-raster fueltypeData fueltype
  ask patches
  [
    ifelse (fueltype <= 0) or (fueltype >= 0)
    []
    [set fueltype -9999]
  ]

  let slopeData gis:load-dataset "Data/Validationagain_2012/slope.asc"
  gis:apply-raster slopeData slope
  ask patches
  [
  ifelse (slope <= 0) or (slope >= 0)
    []
    [set slope -9999]
  ]
  let aspectData gis:load-dataset "Data/Validationagain_2012/aspect.asc"
  gis:apply-raster aspectData aspect
  ask patches
  [
  ifelse (aspect <= 0) or (aspect >= 0)
    []
    [set aspect -9999]
  ]

;  let weatherpatch gis:load-dataset "Data/wpatch2.shp"
;  ask patches [set wpatch? false]
;  ask patches gis:intersecting weatherpatch [set wpatch? true]

  let ignitionData gis:load-dataset "Data/Validationagain_2012/Ignit.shp"
  ask patches gis:intersecting ignitionData
  [set ignition? true]

  if scenario = 6
  [set comparison-perimeter gis:load-dataset "Data/Validationagain_2012/Perim.shp"]


  ask patches gis:intersecting comparison-perimeter [set perim? true]

end

to dynawind ; someday I should make this read from a table....
  ; for now the wind data is just hard-coded here
  if scenario = 3 or scenario = 4 [
    (ifelse
      ticks <= 60 * rescale
      [set wind-speed 21]
      ticks > 60 * rescale and ticks <= 120 * rescale
      [set wind-speed 25]
      ticks > 120 * rescale and ticks <= 180 * rescale
      [set wind-speed 27]
      ticks > 180 * rescale and ticks <= 240 * rescale
      [set wind-speed 37]
      ticks > 240 * rescale and ticks <= 300 * rescale
      [set wind-speed 43]
      ticks > 300 * rescale and ticks <= 360 * rescale
      [set wind-speed 45]
      ticks > 360 * rescale and ticks <= 420 * rescale
      [set wind-speed 46]

      []
  )]

  if scenario = 5 [
    (ifelse
      ticks <= 60 * rescale
      [set wind-speed 16 set wind-direction 270 - 180] ; h1
      ticks > 60 * rescale and ticks <= 120 * rescale
      [set wind-speed 15 set wind-direction 270 - 180] ; h2
      ticks > 120 * rescale and ticks <= 180 * rescale
      [set wind-speed 19 set wind-direction 225 - 180] ; h3
      ticks > 180 * rescale and ticks <= 240 * rescale
      [set wind-speed 21 set wind-direction 225 - 180] ; h4
      ticks > 240 * rescale and ticks <= 300 * rescale
      [set wind-speed 22 set wind-direction 225 - 180] ; h5
      ticks > 300 * rescale and ticks <= 360 * rescale
      [set wind-speed 12 set wind-direction 270 - 180] ; h6
      ticks > 360 * rescale and ticks <= 420 * rescale
      [set wind-speed 5 set wind-direction 135 - 180] ; h7
      ticks > 420 * rescale and ticks <= 480 * rescale
      [set wind-speed 5 set wind-direction 90 - 180] ; h8
      ticks > 480 * rescale and ticks <= 540 * rescale
      [set wind-speed 6 set wind-direction 225 - 180] ; h9
      ticks > 540 * rescale and ticks <= 600 * rescale
      [set wind-speed 3 set wind-direction 315 - 180] ; h10
      ticks > 600 * rescale and ticks <= 660 * rescale
      [set wind-speed 1 set wind-direction 315 - 180] ; h11
      ticks > 660 * rescale and ticks <= 720 * rescale
      [set wind-speed 1 set wind-direction 45 - 180] ; h12

      ticks > 720 * rescale and ticks <= 780 * rescale
      [set wind-speed 1 set wind-direction 225 - 180] ; h13
      ticks > 780 * rescale and ticks <= 840 * rescale
      [set wind-speed 1 set wind-direction 315 - 180] ; h14
      ticks > 840 * rescale and ticks <= 900 * rescale
      [set wind-speed 6 set wind-direction 270 - 180] ; h15
      ticks > 900 * rescale and ticks <= 960 * rescale
      [set wind-speed 3 set wind-direction 270 - 180] ; h16
      ticks > 960 * rescale and ticks <= 1020 * rescale
      [set wind-speed 3 set wind-direction 270 - 180] ; h17
      ticks > 1020 * rescale and ticks <= 1080 * rescale
      [set wind-speed 0.001 set wind-direction 0 - 180] ; h18
      ticks > 1080 * rescale and ticks <= 1140 * rescale
      [set wind-speed 10 set wind-direction 90 - 180] ; h19
      ticks > 1140 * rescale and ticks <= 1200 * rescale
      [set wind-speed 9 set wind-direction 90 - 180] ; h20
      ticks > 1200 * rescale and ticks <= 1260 * rescale
      [set wind-speed 16 set wind-direction 270 - 180] ; h21
      ticks > 1260 * rescale and ticks <= 1320 * rescale
      [set wind-speed 15 set wind-direction 225 - 180] ; h22
      ticks > 1320 * rescale and ticks <= 1380 * rescale
      [set wind-speed 12 set wind-direction 360 - 180] ; h23
      ticks > 1380 * rescale and ticks <= 1440 * rescale
      [set wind-speed 19 set wind-direction 270 - 180] ; h24

      ticks > 1440 * rescale and ticks <= 1500 * rescale
      [set wind-speed 17 set wind-direction 315 - 180] ; h25
      ticks > 1500 * rescale and ticks <= 1560 * rescale
      [set wind-speed 15 set wind-direction 315 - 180] ; h26
      []
  )]
end

to-report fom-stats
  ; calculations for the Figure of Merit.
  set hits count (patches with [burned? = true and perim? = true])
  set misses count (patches with [burned? = false and perim? = true])
  set false-alarms count (patches with [burned? = true and perim? = false])
  report hits / (hits + misses + false-alarms)
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
      fd Fire-trucks-speed
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

  if vectorshow? [vectorshow] ; diagnostic
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
      fueltype = 1 ; C-1 Spruce-Lichen
      [
        set fuel 0.5
        set flam 0.5
        if Visualisation = "FBPscheme" [set pcolor [209 255 115]]
        ;set pcolor [38 41 54]
      ]
      fueltype = 2 ; C-2 Boreal Spruce
      [
        set fuel 0.5
        set flam 0.85
        if Visualisation = "FBPscheme" [set pcolor [34 102 51]]
        ;set pcolor [51 59 71]
      ]
      fueltype = 3 ; C-3 Mature Jack or Lodgepole Pine
      [
        set fuel 0.5
        set flam 0.9
        if Visualisation = "FBPscheme" [set pcolor [131 199 149]]
        ;set pcolor [65 80 87]
      ]
      fueltype = 4 ; C-4 Immature Jack or Lodgepole Pine
      [
        set fuel 0.5
        set flam 0.9
        if Visualisation = "FBPscheme" [set pcolor [112 168 0]]
        ;set pcolor [79 101 104]
      ]
      fueltype = 7 ; C-7 Ponderosa Pine - Douglas-Fir
      [
        set fuel 0.5
        set flam 0.2
        if Visualisation = "FBPscheme" [set pcolor [112 12 242]]
        ;set pcolor [95 120 117]
      ]
      fueltype = 13 ; D-1/D-2 Aspen
      [
        set fuel 0.5
        set flam 0.1
        if Visualisation = "FBPscheme" [set pcolor [196 189 151]]
        ;set pcolor [111 137 127]
      ]
      fueltype = 33 ; O-1a/O-1b Grass
      [
        set fuel 0.4
        set flam 0.6
        if Visualisation = "FBPscheme" [set pcolor [255 255 190]]
        ;set pcolor [144 170 149]
      ]
      fueltype = 101 ; Non-fuel
      [
        set fuel 0
        set flam 0
        set nonfuel? true
        if Visualisation = "FBPscheme" [set pcolor [130 130 130]]

      ]
      fueltype = 102 ; Water
      [
        set fuel 0
        set flam 0
        set water? true
        if Visualisation = "FBPscheme" [set pcolor [115 223 255]]
        ;set pcolor [139 163 189]
      ]
      (fueltype = 640 or fueltype = 650 or fueltype = 660) ; M-1/M-2 Boreal Mixed-wood
      [
        set fuel 0.5
        set flam 0.6
        if Visualisation = "FBPscheme" [set pcolor [255 211 127]]
        ;set pcolor [127 154 138]
      ]


      [set flam flam-level set fuel fuel-level]
    )
    if Visualisation = "Flammability" [
    ifelse not water? and not nonfuel? [
    set pcolor palette:scale-gradient [[144 170 149][111 137 127][95 120 117][65 80 87][51 59 71][38 41 54]] flam 0 1]
    [if water? [set pcolor [139 163 189]] if nonfuel? [set pcolor [188 188 181]]]]

    if Visualisation = "Terrain" [
;      let zenith 60
;      let azimuth 45
;      let hillshading 255 * ((cos(zenith) * cos(slope)) + (sin(zenith) * sin (slope) * cos(azimuth - aspect)))
;      set pcolor scale-color gray hillshading 0 255
      set pcolor hsb aspect slope slope
    ]

    if randomfuel? and not water? and not nonfuel? [
      set fuel 0.1 + random-float 0.9 set flam 0.1 + random-float 0.9
      set pcolor palette:scale-gradient [[144 170 149][111 137 127][95 120 117][65 80 87][51 59 71][38 41 54]] flam 0 1
    ]

  ]
end

;;Visualización dependiendo del fuel y la inflamabilidad
to landscape-validation ; for FBP fuel type maps provided for all of Canada, the numeric code is not the same as provided with Dogrib data.
  ask patches
  [
    (ifelse
      fueltype = 101 ; C-1 Spruce-Lichen
      [
        set fuel 0.5
        set flam 0.5
        if Visualisation = "FBPscheme" [set pcolor [209 255 115]]
        ;set pcolor [38 41 54]
      ]
      fueltype = 102 ; C-2 Boreal Spruce
      [
        set fuel 0.5
        set flam 0.85
        if Visualisation = "FBPscheme" [set pcolor [34 102 51]]
        ;set pcolor [51 59 71]
      ]
      fueltype = 103 ; C-3 Mature Jack or Lodgepole Pine
      [
        set fuel 0.5
        set flam 0.9
        if Visualisation = "FBPscheme" [set pcolor [131 199 149]]
        ;set pcolor [65 80 87]
      ]
      fueltype = 104 ; C-4 Immature Jack or Lodgepole Pine
      [
        set fuel 0.5
        set flam 0.9
        if Visualisation = "FBPscheme" [set pcolor [112 168 0]]
        ;set pcolor [79 101 104]
      ]
      fueltype = 107 ; C-7 Ponderosa Pine - Douglas-Fir
      [
        set fuel 0.5
        set flam 0.2
        if Visualisation = "FBPscheme" [set pcolor [112 12 242]]
        ;set pcolor [95 120 117]
      ]
      fueltype = 108 ; D-1/D-2 Aspen
      [
        set fuel 0.5
        set flam 0.1
        if Visualisation = "FBPscheme" [set pcolor [196 189 151]]
        ;set pcolor [111 137 127]
      ]
      fueltype = 116; O-1a/O-1b Grass
      [
        set fuel 0.4
        set flam 0.6
        if Visualisation = "FBPscheme" [set pcolor [255 255 190]]
        ;set pcolor [144 170 149]
      ]
      fueltype = 122; Veg non-fuel
      [
        set fuel 0.4
        set flam 0.3
        if Visualisation = "FBPscheme" [set pcolor [255 255 220]]
        ;set pcolor [144 170 149]
      ]
      fueltype = 120; wetland
      [
        set fuel 0.4
        set flam 0.05
        if Visualisation = "FBPscheme" [set pcolor [50 190 205]]
        ;set pcolor [144 170 149]
      ]
      fueltype = 121; urban
      [
        set fuel 0.01
        set flam 0.5
        if Visualisation = "FBPscheme" [set pcolor [240 125 139]]
        ;set pcolor [144 170 149]
      ]
      fueltype = 119 or fueltype = -9999; Non-fuel
      [
        set fuel 0
        set flam 0
        set nonfuel? true
        if Visualisation = "FBPscheme" [set pcolor [130 130 130]]

      ]
      fueltype = 118 ; Water
      [
        set fuel 0
        set flam 0
        set water? true
        if Visualisation = "FBPscheme" [set pcolor [115 223 255]]
        ;set pcolor [139 163 189]
      ]
      (fueltype = 109) ; M-1/M-2 Boreal Mixed-wood
      [
        set fuel 0.5
        set flam 0.6
        if Visualisation = "FBPscheme" [set pcolor [255 211 127]]
        ;set pcolor [127 154 138]
      ]

      [set flam 0 set fuel 0]
    )
    if Visualisation = "Flammability" [
    ifelse not water? and not nonfuel? [
    set pcolor palette:scale-gradient [[144 170 149][111 137 127][95 120 117][65 80 87][51 59 71][38 41 54]] flam 0 1]
    [if water? [set pcolor [139 163 189]] if nonfuel? [set pcolor [188 188 181]]]]

    if Visualisation = "Terrain" [
;      let zenith 60
;      let azimuth 45
;      let hillshading 255 * ((cos(zenith) * cos(slope)) + (sin(zenith) * sin (slope) * cos(azimuth - aspect)))
;      set pcolor scale-color gray hillshading 0 255
      set pcolor hsb aspect slope slope
    ]

    if randomfuel? and not water? and not nonfuel? [
      set fuel 0.1 + random-float 0.9 set flam 0.1 + random-float 0.9
      set pcolor palette:scale-gradient [[144 170 149][111 137 127][95 120 117][65 80 87][51 59 71][38 41 54]] flam 0 1
    ]

  ]
end

;;Calculos del viento
to wind-calc
  let spec-rescale rescale
  if rescale > 1 [set spec-rescale rescale ^ 0.25]
  set active-cells patches with [any? fires-here or any? fires in-radius (4 * spec-rescale)] ; size of this is a parameter I haven't even touched
  set active-wind patches with [any? fires in-radius (6 * spec-rescale )]

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
  if any? fires[
    ask fire-trucks [
      let nearest-fire min-one-of fires [distance myself]
      face nearest-fire

      apagar_fuego

      check-and-extinguish-fires
    ]
  ] if not any? fires [
    print "No hay fuegos por apagar."
  ]
end

to move-fire-trucks-further
  if any? fires[
    ask fire-trucks [
      let further-fire max-one-of fires [distance myself]
      face further-fire

      apagar_fuego

      check-and-extinguish-fires
    ]
  ] if not any? fires [
    print "No hay fuegos por apagar."
  ]
end

;;Estrategia de camiones de bomberos para dirigirse a fuego de mayor RoS
to move-fire-trucks-MaxRoS
  if any? fires[
    ask fire-trucks [
      let max_RoS max-one-of fires [RoS]
      face max_RoS

      apagar_fuego

      check-and-extinguish-fires
    ]
  ] if not any? fires [
    print "No hay fuegos por apagar."
  ]
end

;; Estrategia de camiones de bomberos para dirigirse a fuego de menor RoS
to move-fire-trucks-MinRoS
  if any? fires [
    ask fire-trucks [
      let min_RoS min-one-of fires [RoS]
      face min_RoS

      check-and-extinguish-fires

      apagar_fuego
    ]
  ] if not any? fires [
    print "No hay fuegos por apagar."
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
    fd Fire-trucks-speed  ; Velocidad del camión de bomberos en casillas por tick de reloj (desde la interfaz)
    set contador-ticks 0
    set color yellow
  ]
end

;;Calculos para la propagación del fuego
to spread
  set max-density max [density] of fires
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
 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


 ;;;;;;;;;;;; This recombines components into magnitude and direction for the fire agents
    let Cmag ((Cx ^ 2) + (Cy ^ 2)) ^ 0.5
    let Cang atan Cx Cy
    set heading Cang
    set RoS Cmag

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
    if stamp? [stamp]
 ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

 ;; Para que se eliminen los fuegos que salen de los extremos de la pantalla



 ;;;;;;;;;;;; Pre-heating
    ask patch-ahead RoS [if flam < 1 [set flam flam + ( 0.005 * [RoS] of myself) / (1 + distance myself) ^ 2]]

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

;;función show comparison
to show-comparison

  let features gis:feature-list-of comparison-perimeter
  foreach features
  [ z ->
    let vertex-list-z gis:vertex-lists-of z
    foreach vertex-list-z
    [ y ->
      let vertex-list y

    foreach  vertex-list
    [ x ->
      let one-vertex gis:location-of x
      create-turtles 1
      [
        setxy item 0 one-vertex item 1 one-vertex
        set color yellow
        set shape "dot"
      ]
    ]
    ]
  ]
  ;let vertex-list gis:vertex-lists-of item 0 features
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
  gis:store-dataset burnscar (word "Raster_out/" folder-name "/V23_" counter "_scen_" scenario "_scale_" rescale "_" (precision fom-stats 2) ".asc")

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
  gis:store-dataset burnscarfom (word "Raster_out/" folder-name "/V23_fom_" counter "_scen_" scenario "_scale_" rescale "_" (precision fom-stats 2) ".asc")

  ;Third is arrival time
  let arrivaltime gis:patch-dataset arrival-time
  gis:store-dataset arrivaltime (word "Raster_out/" folder-name "/AT_" counter "_scen_" scenario "_scale_" rescale "_" (precision fom-stats 2) ".asc")

end

to vectorise
  ask patches [
    sprout-vectors 1
    [set color white
      set shape "line half"
      set size 0.4
      set heading [winddir] of patch-here]]
end

;;Si se activa esta opción se muestran los vectores a medida que se van calculando
to vectorshow

  ask vectors
  [
    if windX > 0 or windX < 0
    [set heading atan windX windY]
    set size (4 * windspe) ^ 0.5
    ;set heading [winddir] of patch-here
    set color palette:scale-gradient [[255 255 255] [204 227 222] [107 144 128]] [windspe] of patch-here 0 100 ;[164 195 178]
  ]
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
1354
578
-1
-1
5.042016806722689
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
177
0
110
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
9
214
181
247
wind-speed
wind-speed
0.01
200
24.01
1
1
NIL
HORIZONTAL

INPUTBOX
332
76
387
154
stoptime
1530.0
1
0
Number

SLIDER
9
248
181
281
wind-direction
wind-direction
0
360
55.0
5
1
NIL
HORIZONTAL

SLIDER
205
337
297
370
f1
f1
0
1
0.2
0.01
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
9
343
81
388
NIL
count fires
17
1
11

MONITOR
81
343
181
388
NIL
count active-cells
17
1
11

MONITOR
873
600
957
645
RoS in Cell/Tick
mean [RoS] of fires
4
1
11

MONITOR
9
387
181
432
Mean wind speed active
mean [windspe] of active-cells
4
1
11

SLIDER
205
370
297
403
f2
f2
0
1
0.81
0.01
1
NIL
HORIZONTAL

MONITOR
9
432
181
477
NIL
mean [collinear] of fires
4
1
11

SLIDER
9
311
181
344
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
9
280
181
313
flam-level
flam-level
0
1
0.5
0.1
1
NIL
HORIZONTAL

SLIDER
205
532
397
565
burnscaler
burnscaler
0
30
17.0
1
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
0 1 2 3 4 5 6
5

PLOT
873
645
1178
825
Agreement
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"" ""
PENS
"Hits" 1.0 0 -13840069 true "" "plot hits"
"Misses" 1.0 0 -2674135 true "" "plot misses"
"False alarms" 1.0 0 -13345367 true "" "plot false-alarms"

MONITOR
1178
645
1261
690
Figure of Merit
fom-stats
3
1
11

MONITOR
1178
690
1261
735
Hits
hits
3
1
11

MONITOR
1178
735
1261
780
Misses
misses
3
1
11

MONITOR
1178
780
1261
825
False alarms
false-alarms
3
1
11

SLIDER
206
589
302
622
w1
w1
0
1
0.44
0.02
1
NIL
HORIZONTAL

SLIDER
302
589
398
622
w2
w2
0
1
0.24
0.02
1
NIL
HORIZONTAL

MONITOR
9
521
181
566
NIL
mean [windmod] of fires
4
1
11

INPUTBOX
205
454
255
514
a
0.57
1
0
Number

INPUTBOX
276
455
326
515
b
180.0
1
0
Number

INPUTBOX
347
455
397
515
k
16.0
1
0
Number

INPUTBOX
297
337
347
403
w3
4.2
1
0
Number

INPUTBOX
347
337
397
403
m1
0.2
1
0
Number

MONITOR
1097
600
1261
645
avg RoS start to finish (m/min)
avgRoS * 200
4
1
11

MONITOR
1031
600
1097
645
Area (ha)
area
0
1
11

BUTTON
6
88
98
121
NIL
show-comparison
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

INPUTBOX
387
76
438
154
rescale
1.0
1
0
Number

SLIDER
206
10
332
43
counter
counter
0
100
94.0
1
1
NIL
HORIZONTAL

SLIDER
297
403
397
436
s1
s1
0
0.2
0.019
0.001
1
NIL
HORIZONTAL

SWITCH
206
43
332
76
vectorshow?
vectorshow?
1
1
-1000

SLIDER
205
403
297
436
d1
d1
0
5
2.5
0.5
1
NIL
HORIZONTAL

MONITOR
9
477
181
522
NIL
mean [density] of fires
4
1
11

MONITOR
9
566
181
611
NIL
mean [density-mod] of fires
4
1
11

SWITCH
206
76
332
109
stamp?
stamp?
1
1
-1000

MONITOR
957
600
1031
645
RoS in m/min
mean [RoS] of fires * 200
4
1
11

PLOT
450
600
873
826
Diagnostics
NIL
NIL
0.0
10.0
0.0
1.0
true
true
"" ""
PENS
"RoS" 1.0 0 -2674135 true "" "plot mean [RoS] of fires"
"WS" 1.0 0 -8990512 true "" "plot mean [windspe] of active-cells"
"collinear" 1.0 0 -14985354 true "" "plot mean [collinear] of fires"
"windmod" 1.0 0 -865067 true "" "plot mean [windmod] of fires"
"density-mod" 1.0 0 -1184463 true "" "plot mean [density-mod] of fires"
"f2-effective" 1.0 0 -16645118 true "" "plot mean [(f2 * (1 - windmod / 2))] of fires"
"0" 1.0 0 -4539718 true "" "plot 0"

SWITCH
332
10
438
43
spotting?
spotting?
0
1
-1000

SWITCH
332
43
438
76
randomfuel?
randomfuel?
1
1
-1000

CHOOSER
206
109
332
154
Visualisation
Visualisation
"Flammability" "FBPscheme" "Terrain"
0

BUTTON
98
88
179
121
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
205
214
398
274
folder-name
Tijuana
1
0
String

BUTTON
205
274
398
307
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
208
189
395
233
Name of folder where Monte Carlo simulation results will be stored.
9
0.0
1

TEXTBOX
208
320
398
338
Parameters in Spread procedure
13
0.0
1

TEXTBOX
218
438
388
471
Parameters for windmod eq.
13
0.0
1

TEXTBOX
216
513
391
532
Rate of consumption, inverse
13
0.0
1

TEXTBOX
216
572
385
606
Parameters for wind mixing
13
0.0
1

BUTTON
6
121
133
154
show-arrival-time
cd\nask patches with [burned?]\n[\n  set pcolor palette:scale-gradient [[26 83 92][74 111 165][53 167 255][181 226 250][249 247 243][237 222 164][247 160 114][255 89 100][95 15 64]] (arrival-time) 0 (stoptime)\n]
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
7
166
93
199
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
128
164
188
209
ticks/sec
performance
4
1
11

TEXTBOX
12
623
162
641
FIRETRUCKS
10
0.0
1

SLIDER
9
724
181
757
Fire-trucks-speed
Fire-trucks-speed
0
1
0.5
0.1
1
NIL
HORIZONTAL

BUTTON
10
639
113
672
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
9
678
174
723
Estrategy
Estrategy
"MIN_DISTANCE" "MAX_DISTANCE" "MAX_RoS" "MIN_RoS"
0

SLIDER
10
759
182
792
Delay
Delay
0
10
10.0
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
