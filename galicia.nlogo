;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;; Agent-Based Wildfire Simulation Environment
;;;;; Author: Adriano Miranda Seoane
;;;;; 2024

extensions [gis palette string]

globals
[
  active-cells
  active-wind

  RoS-list
  avgRoS

  area

  max-density

  firetruck-created ;;Flag para saber si se ha creado un firetruck para click-Fire-truck
  num-fire-trucks ;Numero de fire-trucks

  t ;;Para la función de vectorizar
  t30

  messages
  message-types
  finished_messages ;Flag para saber cuando termina la comunicación entre agentes

  focos_incendio ;Lista de los focos de incendio (cell dónde se hace el ignite)
]

breed [fires fire]
breed [coordinadores coordinador]
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
  closest-fire-distance ;; distancia al fuego más cercano
  ;Atributos para estrategias de comunicación:
  apago_fuego ; Flag para saber si soy el fire-truck que debe apagar el fuego
  disponible
  distancesList ;Lista de distancias mínimasa fuegos
  requests1 ;Lista de requests recibidos tipo 1
  requests2 ;Lista de requests recibidos tipo 2
  ;Coordenadas hacia donde debe dirigirse
  target-x
  target-y
]

;Coordinador para comunicación
coordinadores-own
[
  distancesList ;Lista de distancias mínimasa fuegos
  requests1 ;Lista de requests recibidos tipo 1
  requests2 ;Lista de requests recibidos tipo 2
]

patches-own
[
  fuel ;Valor del fuel
  flam ;Valor de inflamabilidad
  cluster ;Cluster al que pertenece
  windspe ;Velocidad del viento
  winddir ;Dirección del viento
  globspe
  globdir

  ;;Para controlar la posición y movimiento
  fireX
  fireY

  windX
  windY

  globX
  globY

  fueltype  ;tipo de modelo combustible
  landusetype  ;tipo de uso de suelo (para las casillas que no tienen vegetación
  slope  ;pendiente del patch
  fuera_mapa  ;Para ningún agente sobresalga los límites del mapa

  water?  ;;Flag para saber en qué patches hay agua

  wpatch?
  ignition? ;Patches dónde comienza el fuego
  burned?  ;;Patches que han sido quemados
  arrival-time

  pburned

]

to setup
  ca
  set RoS-list []
  set firetruck-created false
  setup-message-types
  set finished_messages false
  set messages []
  set num-fire-trucks 0
  set focos_incendio []
  create-coordinadores 1[
    set distancesList []
    set requests1 []
    set requests2 []
  ]
  if scenario = 0  ; manual wind speed and direction input
    [
      ;Cada tick representa 1 min
      set stoptime 1440 * rescale ; 1 día (24 horas) hours
      set wind-direction 55

      ;Cargar el mapa
      load-GIS-0
      ;Mostrar el mapa
      landscape
      ask patches with [ignition?] [ignite]
    ]

  ;;if vectorshow? [vectorise] ; diagnostic

  reset-ticks
end


to load-GIS-0
  ;; Cargar los archivos de datos
  let fueltypeData gis:load-dataset "DATA_GAL/modelo_comb_cellsize.asc"
  let landuseData gis:load-dataset "DATA_GAL/uso_suelo_cellsize.asc"
  let slopeData gis:load-dataset "DATA_GAL/pendiente.asc"

  ;; Obtener las dimensiones del mapa y redimensionar el mundo NetLogo
  let spec-rescale 1  ;; Asumimos que rescale es 1, cambiar si es necesario
  let new-world-width ((gis:width-of fueltypeData) * spec-rescale)
  let new-world-height ((gis:height-of fueltypeData) * spec-rescale)

  ;print((gis:width-of fueltypeData))
  ;print(gis:height-of fueltypeData)
  resize-world 0 (new-world-width - 1) 0 (new-world-height - 1)
  set-patch-size 900 / new-world-width  ; Tamaño de parche relativo al tamaño del mundo
  let envelope gis:envelope-of fueltypeData
  gis:set-world-envelope envelope

  ;; Aplicar el raster de combustible
  gis:apply-raster fueltypeData fueltype
  gis:apply-raster landuseData landusetype
  gis:apply-raster slopeData slope

  ;; Inicializar variables de parches
  ask patches [
    set ignition? false
    set burned? false
    set water? false
    set fuera_mapa false
  ]
  ;print("fueltype del patch 83 80 :")
  ;show [fueltype] of patch 83 80

  ;; Rellenar los valores de fueltype con datos de UsoSuelo donde fueltype es 0
  ask patches [
    ;Si no hay datos sobre la vegetación entonces utilizo los datos sobre el uso del terreno.
    if (fueltype != 1) and (fueltype != 2) and (fueltype != 3) and (fueltype != 4) and (fueltype != 5) and (fueltype != 6) and (fueltype != 7) and (fueltype != 8) and (fueltype != 9) and (fueltype != 10) and (fueltype != 11) and (fueltype != 12) and (fueltype != 13)  [

      let newfueltype [landusetype] of patch pxcor pycor
      set fueltype newfueltype
    ]
  ]

end

to setup-message-types
  set message-types ["Agree" "Inform" "Call_for_proposal" "Query_Ref" "Refuse" "Request"]
end

to send-message [sender receiver message-type content]
  ;fire-trucks que reciven el mensaje

  ask receiver [
    set messages lput (list sender receiver message-type content) messages
  ]
end

to process-messages
  let processed-messages []

  foreach messages [message ->
    let sender item 0 message
    let receiver item 1 message
    let message-type item 2 message
    let content item 3 message

    ifelse message-type = "Request" [
      ; Procesar Request

      show (word "Request received from " sender " with content: " content)

      ; Aquí se podría enviar automáticamente el Inform, pero ya lo hacemos en move-fire-trucks-nearest
    ] [
      if message-type = "Inform" [
        ; Procesar Inform
        show (word "Inform received from " sender " with content: " content)
      ]
      if message-type = "Agree" [
        ; Procesar Agree
        show (word "Agree received from " sender " with content: " content)
      ]
      if message-type = "Refuse" [
        ; Procesar Refuse
        show (word "Refuse received from " sender " with content: " content)
      ]
      if message-type = "Call_for_proposal" [
        ; Procesar Refuse
        show (word "Call for proposal received from " sender " with content: " content)
      ]
    ]
    set processed-messages lput message processed-messages
  ]
  set messages filter [message -> not member? message processed-messages] messages
end

;Transformación de coordenadas geográficas a coordenadas en nuestro documento .asc
to geoCoords-ascCoords
  ;; Coordenadas de ejemplo del shapefile
  ;let shapefile-x 50000
  ;let shapefile-y 4700000
  let shapefile-x UTM-X
  let shapefile-y UTM-Y

  ;Convierto string a cadena
  let numeroX read-from-string shapefile-x  ;; Convertir cadena a número
  let numeroY read-from-string shapefile-y  ;; Convertir cadena a número

  ;; Convertir a coordenadas de la cuadrícula del archivo .asc
  let asc-coords shapefile-to-asc-coords numeroX numeroY

  ;; Extraer columna y fila
  let col item 0 asc-coords
  let row item 1 asc-coords

  ;; Mostrar las coordenadas convertidas
  ;show (word "Columna: " col " Fila: " row)
  ;Prendo fuego en las coordenadas especificadas por el usuario
  ask patch col row
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
    stop
end

to-report shapefile-to-asc-coords [x y]
  ;; Extraer parámetros del archivo .asc
  let xllcorner -14131.897400000133
  let yllcorner 4637883.999800000340
  let cellsize 666.513583548387

  ;; Calcular las coordenadas de la cuadrícula (columna, fila) basadas en las coordenadas reales (x, y)
  let col floor ((x - xllcorner) / cellsize)
  let row floor ((y - yllcorner) / cellsize)

  ;; Reportar las coordenadas de la cuadrícula
  report list col row
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
  [
    ask coordinadores[
      set focos_incendio lput list mouse-xcor mouse-ycor focos_incendio
      ;print(focos_incendio)
    ]
    ask patch mouse-xcor mouse-ycor
    [
      let directions [0 90 180 270]
      let i 0
      repeat 4
      [sprout-fires 1
        [
          set heading item i directions
          set size 2
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
      set disponible false
      set apago_fuego false ;Flag para saber si soy el fire-truck que debe apagar el fuego
      set requests1 [] ;Para saber si ha recibido un Request
      set requests2 [] ;Para saber si ha recibido un Request
      set apagando_fuego false
      set truck-size 3
      set contador-ticks 0
      set num-fire-trucks num-fire-trucks + 1
      set size truck-size ; Tamaño de los camiones de bomberos
      set color yellow ; Asigna un color amarillo al camión de bomberos
      fd Firetrucks-speed
      setxy mouse-xcor mouse-ycor ; Establece la posición del camión de bomberos donde se hizo clic
      set  distancesList[] ;Lista de distancias mínimasa fuegos
      set target-x 0
      set target-y 0
    ]
    set firetruck-created true
  ]
  if not mouse-down? ;;Reinicia variable al soltar botón del ratón
  [
    set firetruck-created false
  ]
end

;; Calcular la distancia al fuego
to calculate-closest-fire-distance
  let nearest-fire min-one-of fires [distance myself]
  ifelse any? fires [
    set closest-fire-distance distance nearest-fire
  ] [
    set closest-fire-distance 1000000 ;; Si no hay fuegos, establecer distancia a infinito
  ]
end

to go
  tick

  ifelse not any? fires
  [
    set avgRoS mean RoS-list
    stop
  ][
    let RoS-at-tick mean [RoS] of fires
    set RoS-list lput RoS-at-tick RoS-list
  ]

  ;;if dynawind? [dynawind]
  wind-calc
  spread
  estrategia
  consume

  ;;check-and-extinguish-fires
  ask fire-trucks [
    if apagando_fuego = true [contar-ticks]

  ]

  ;cada pixel = 666 metros x 666 metros  = 443.3556 m2 (47,6 ha) (esta info. está en el .asc)
  set area (count patches with [burned?] * 44.3556 ) ;pixeles quemados * hectareas de cada pixel
  ;;if vectorshow? [vectorshow] ; diagnostic

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
  if Estrategy = "PROP_ONE_MIN_DIST"[proposal-one-min-distance]
  if Estrategy = "COORD_ONE_MIN_DIST"[coordinated-one-min-distance]
  if Estrategy = "ONE_MIN_DIST"[one-min-distance]
  if Estrategy = "ALL_MIN_DIST"[all-min-distance]
  if Estrategy = "DISTRIBUTED_ATTACK"[distributed-attack]
end

;;Visualizacion "FBPscheme": Depende del fueltype (nivel de fuel y flam)
;;Visualización "Terrain": depende de slope
;;Visualización "Flamability": Depende solo de la inflamabilidad (flam)
to landscape

  ask patches
  [

    (ifelse
      ;;Colores: -Escala de verdes:mientras más oscuro media entre fuel y flam más alta
      ;;-azul: Zonas dónde hay agua -gris: dónde no se propaga el fuego (fuel=0 y flam=0)

      fueltype = 1 ; Pasto fino, seco y bajo. Pl leñosas < 1/3 de la superficie
      [
        set fuel 0.3 ;Cubre poco de la superficie por lo tanto poca densidad
        set flam 0.7; Valoración de chatgpt entre 0.6 y 0.8.
        set cluster "pasto poco denso"
        if Visualisation = "Fueltype" [set pcolor [0 100 0]] ;;Verde
        ;set pcolor [51 59 71]
      ]
      fueltype = 2 ; Pasto fino, seco y bajo. Pl leñosas cubren  1/3 a 2/3 de la superficie
      [
        set fuel 0.6 ;Como el 1 pero cubre más superficie por lo tanto más denso
        set flam 0.7; Valoración de chatgpt entre 0.6 y 0.8
        set cluster "pasto medianamente denso"
        if Visualisation = "Fueltype" [set pcolor [0 83 0]] ;;Verde
        ;set pcolor [65 80 87]
      ]
      fueltype = 3 ;Pasto denso, grueso, seco y alto (h>1m). Pl leñosas dispersas
      [
        set fuel 0.8 ;Como el anterior pero más denso
        set flam 0.7 ;;Valoración de chatgpt entre 0.6 y 0.8
        set cluster "pasto medianamente denso"
        if Visualisation = "Fueltype" [set pcolor [0 64 0]] ;;Verde
        ;set pcolor [65 80 87]
      ]

      ;Matorral  denso y  verde (h>2 m). Propagación del fuego por las copas de las pl.; ; Matorral  denso y  verde (h<1 m). Propagación del fuego por la hojarasca y el pasto;
      (member? fueltype [4 5])
      [
        set fuel 0.8 ;alto puesto que es denso
        set flam 0.7 ;según chatgpt oscila entre 0.6 y 0.9
        set cluster "matorrales densos"
        if Visualisation = "Fueltype" [set pcolor [0 64 0]] ;;Azul
      ]

      ;Parecido al modelo 5 pero con especies más inflamables o con restos de podasy pl de mayor talla; Matorral de especies muy inflamables (h: 0,5-2 m) situado como sotobosque de masas de coníferas
      (member? fueltype [6 7])
      [
        set fuel 0.5 ;Medio puesto que no especifica que sean densos
        set flam 0.9 ;especifica alta inflamabilidad
        set cluster "matorrales alta inflamabilidad"
        if Visualisation = "Fueltype" [set pcolor [0 71 0]] ;;Azul
      ]

      fueltype = 8 ;Bosque denso, sin matorral. Propagación del fuego por hojarasca muy compacta
      [
        set fuel 0.8 ; especifica que es denso
        set flam 0.7 ;entre 0.7 y 0.8 según chatgpt
        set cluster "bosque denso"
        if Visualisation = "Fueltype" [set pcolor [0 64 0]] ;;Verde
        ;set pcolor [95 120 117]
      ]
      fueltype = 9 ;Parecido al modelo 8 pero con hojarasca menos compacta formada por acículas largas y rígidas o follaje de frondosas de hojas grandes
      [
        set fuel 0.6 ;Igual que el 8 pero menos compacto por lo tanto menos denso
        set flam 0.7 ;Igual que el 8
        set cluster "bosque poco denso"
        if Visualisation = "Fueltype" [set pcolor [0 83 0]] ;;Verde
        ;set pcolor [95 120 117]
      ]
      fueltype = 10 ;Bosque con gran cantidad de leña y árboles caídos, como consecuencia de vendavales, plagas intensas, etc.
      [
        set fuel 0.5 ; No tenemos información sobre la densidad
        set flam 0.8 ;Valoración según chatgpt
        set cluster "arboles caidos"
        if Visualisation = "Fueltype" [set pcolor [0 83 0]] ;;Verde
        ;set pcolor [95 120 117]
      ]
      ;Bosque claro y fuertemente aclarado. Restos de poda o aclarado dispersos con pl herbáceas rebrotando; Predominio de los restos sobre el arbolado. Restos de poda o aclareo cubriendo todo el suelo
      (member? fueltype [11 12])
      [
        set fuel 0.3;Disperso por lo tanto poco denso
        set flam 0.5;Valoración de chatgpt entre 0.4 y 0.6
        set cluster "bosques claros"
        if Visualisation = "Fueltype" [set pcolor [0 115 50]] ;; Verde
        ;set pcolor [95 120 117]
      ]
      fueltype = 13 ;Grandes acumulaciones de restos gruesos y pesados, cubriendo todo el suelo.
      [
        set fuel 0.9 ; Alta densidad al cubrir todo el suelo con restos gruesos y pesados
        set flam 0.9 ;Valoración de chatgpt entre 0.9 y 1.0
        set cluster "grandes acumulaciones"
        if Visualisation = "Fueltype" [set pcolor [0 26 0]] ;;Verde
        ;set pcolor [95 120 117]
      ]

      ;;USO DE SUELO para patches sin información de modelo Combustible

      ;Playas Dunas y Arenales; Primario;Industrial;Terciario;Equipamiento Dotaciona;Otras superficies artificiales; Talas; Superficies arboladas quemadas; Cortafuegos; SUperficies desarboladas quemadas;
      ;Acantilados marinos; Afloramientos rocosos; Canchales; Roturado no agrícola; Zonas pantanosas; Turberas; Marismas; Estuarios; Urbano Continuo; Urbano Discontinuo;
      ;Transportes; Energía; Telecomunicaciones; Residuos; Otras zonas erosionadas;
      (member? fueltype [41 82 83 84 85 87 101 102 103 432
        441 442 443 452 511 512 521 622 811 812
        861 862 864 865 4542])
      [
        set fuel 0.0
        set flam 0.0
        set cluster "sin vegetacion"
        if Visualisation = "Fueltype" [set pcolor [155 155 155]]  ;;Gris
      ]

      ;Cursos de agua; Suministros de agua; Lagunas; Pantano o embalse; Laguna de alta montaña
      (member? fueltype [611 863 6121 6122 6123])
      [
        set fuel 0.0
        set flam 0.0
        set water? true
        set cluster "agua"
        if Visualisation = "Fueltype" [set pcolor [34 113 179]]  ;;Azul
      ]

      ;Cultivos; Cultivos con arbolado disperso; Prado; Prado con setos; Mosaico Agrícola con artificial;
      (member? fueltype [71 72 73 74 75 ])
      [
        set fuel 0.2
        set flam 0.2
        set cluster "poca vegetacion"
        if Visualisation = "Fueltype" [set pcolor [28 120 49]] ;;Vede Oscuro
      ]


      [
        ;;En caso de no ser ninguno de estos tipos:
        set fuera_mapa true
        set fuel 0.0
        set flam 0.0
        set cluster "fuera de mapa"
        if Visualisation = "Fueltype" [set pcolor [173 216 230] ] ;Azul claro
        ;set pcolor [38 41 54]
      ]
    )

;; Slope visualisation
if Visualisation = "Slope" [
  ifelse slope < 5 [set pcolor [245 222 179]] ; Brown 1
  [
    ifelse slope < 10 [set pcolor [222 184 135]] ; Brown 2
    [
      ifelse slope < 15 [set pcolor [210 180 140]] ; Brown 3
      [
        ifelse slope < 20 [set pcolor [160 82 45]] ; Brown 4
        [
          ifelse slope < 25 [set pcolor [139 69 19]] ; Brown 5
          [
            ifelse slope < 30 [set pcolor [110 44 0]] ; Brown 6
            [
              ifelse slope < 35 [set pcolor [101 67 33]] ; Brown 7
              [
                ifelse slope < 40 [set pcolor [92 51 23]] ; Brown 8
                [
                  ifelse slope < 45 [set pcolor [79 60 38]] ; Brown 9
                  [
                    ifelse slope < 50 [set pcolor [70 42 0]] ; Brown 10
                    [
                      ifelse slope < 60 [set pcolor [60 30 10]] ; Brown 11
                      [
                        ifelse slope < 70 [set pcolor [50 20 0]] ; Brown 12
                        [
                          ifelse slope < 80 [set pcolor [40 10 0]] ; Brown 13
                          [
                            ifelse slope < 90 [set pcolor [30 0 0]] ; Brown 14
                            [
                              ifelse slope < 100 [set pcolor [20 0 0]] ; Brown 15
                              [
                                ifelse slope < 110 [set pcolor [10 0 0]] ; Brown 16
                                [
                                  ifelse slope < 120 [set pcolor [5 0 0]] ; Brown 17
                                  [
                                    ifelse slope < 130 [set pcolor [3 0 0]] ; Brown 18
                                    [
                                      ifelse slope < 140 [set pcolor [1 0 0]] ; Brown 19
                                      [
                                        ifelse slope < 150 [set pcolor [0 0 0]] ; Brown 20
                                        [
                                          set pcolor [0 0 0] ; Default brown for slope >= 150
                                        ]
                                      ]
                                    ]
                                  ]
                                ]
                              ]
                            ]
                          ]
                        ]
                      ]
                    ]
                  ]
                ]
              ]
            ]
          ]
        ]
      ]
    ]
  ]
]



   ;; Flammability visualisation: Escala de naranjas (más oscuro implica más inflamable)
    if Visualisation = "Flammability" [
      ifelse flam < 0.1 [set pcolor [255 235 205]]
      [
        ifelse flam < 0.2 [set pcolor [255 213 153]]
        [
          ifelse flam < 0.3 [set pcolor [255 191 102]]
          [
            ifelse flam < 0.4 [set pcolor [255 170 51]]
            [
              ifelse flam < 0.5 [set pcolor [255 148 0]]
              [
                ifelse flam < 0.6 [set pcolor [223 127 0]]
                [
                  ifelse flam < 0.7 [set pcolor [191 106 0]]
                  [
                    ifelse flam < 0.8 [set pcolor [159 85 0]]
                    [
                      ifelse flam < 0.9 [set pcolor [127 64 0]]
                      [set pcolor [95 42 0]] ; Para flam >= 0.9
                    ]
                  ]
                ]
              ]
            ]
          ]
        ]
      ]
    ]

    ;; Fuel visualisation: Escala de naranjas (más oscuro implica más inflamable)
    if Visualisation = "Fuel" [
      ifelse fuel < 0.1 [set pcolor [255 235 205]]
      [
        ifelse fuel < 0.2 [set pcolor [255 213 153]]
        [
          ifelse fuel < 0.3 [set pcolor [255 191 102]]
          [
            ifelse fuel < 0.4 [set pcolor [255 170 51]]
            [
              ifelse fuel < 0.5 [set pcolor [255 148 0]]
              [
                ifelse fuel < 0.6 [set pcolor [223 127 0]]
                [
                  ifelse fuel < 0.7 [set pcolor [191 106 0]]
                  [
                    ifelse fuel < 0.8 [set pcolor [159 85 0]]
                    [
                      ifelse fuel < 0.9 [set pcolor [127 64 0]]
                      [set pcolor [95 42 0]] ; Para fuel >= 0.9
                    ]
                  ]
                ]
              ]
            ]
          ]
        ]
      ]
    ]
    ;set flam flam-level ;para establecer todos los patches con el mismo nivel de flam y fuel
    ;set fuel fuel-level
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

;Estrategia sin comunicación, simplemente todos los fire-trucks se desplazan hacia el fuego más cercano.
to all-min-distance
  ask fire-trucks [
      let nearest-fire min-one-of fires [distance myself]
      if any? fires[
        face nearest-fire
        apagar_fuego
        check-and-extinguish-fires
        set apago_fuego true
      ]if not any? fires [
      print "No hay fuegos por apagar."
      ]
    ]
end

;; Estrategia para enviar mensajes y el fire-truck más cercano al fuego que se desplace para extinguirlo.
to one-min-distance

  ;Todos los agentes envían Requet1 a todos los demás agentes y contestan con un Inform
  if finished_messages = false [
    ask fire-trucks [
      ask other fire-trucks [

        send-message myself self "Request" "¿Cuál es tu distancia al fuego más cercano?";Envío mensaje Request de distancia, debe ser contestado con un inform
        process-messages
        ask myself [set requests1 lput myself requests1]

      ]
    ]
  ]

   ask fire-trucks [
      ask other fire-trucks [
        if  requests1 != [] [
          foreach requests1 [ elemento ->
            let dist distance min-one-of fires [distance myself]  ;Esta es la distancia en casillas
            let distKm dist * 0.666  ;Distancia en Km
            ask elemento[
              send-message myself elemento "Inform" (word "Distancia al fuego más cercano: " distKm " Km")  ;Envío mensaje Inform
              process-messages
           ]
            ;;Cada firetruck añade a su lista las distancias mínimas del resto de firetrucks
          ask other fire-trucks[

            if not member? dist distancesList ;si no está en lista lo añado
            [
              set distancesList lput dist distancesList
            ]  ; Añadir la distancia a la lista de distancias recibidas
          ]
        ]
        set requests1 []
      ]
    ]
  ]

  ;Todos los agentes envían Requet2 a todos los demás agentes y contestan con un Inform
  if finished_messages = false [
    ask fire-trucks [
      ask other fire-trucks [

        send-message myself self "Request" "¿VAS A APAGAR EL FUEGO?";Envío mensaje Request acción ir apagar el fuego. Debe ser contestado con un agree si la distancia es mínima o un Refuse en caso contrario
        process-messages
        ask myself [set requests2 lput myself requests2]

      ]
    ]

    set finished_messages true
  ]

  ; Si recibi un request de tipo 2 envío un Agree o un refuse
  ask fire-trucks [

    if  requests2 != [] [
      foreach requests2 [ elemento ->
      ;Compruebo si mi distancia minima la fuego es menor que la del resto
        calculate-closest-fire-distance
        let my_dist closest-fire-distance
        let soy_menor true
        foreach distancesList [element ->
          if element < my_dist [
            set soy_menor false
          ]
        ]

        if(soy_menor)[
          ask elemento[
            send-message myself elemento "Agree" (word "Action: Apagar fuego. Condition: Soy el fire-truck más próximo a fuego ")  ;Envío mensaje Agree
            process-messages
          ]
          set apago_fuego true
        ]
        if not (soy_menor) [
          ask elemento[
            send-message myself elemento "Refuse" (word "Action: No Apagar fuego. Reason: No soy el fire-truck más cercano ")  ;Envío mensaje Refuse
            process-messages
          ]
        ]
      ]
    set requests2 []
    ]
  ]

  ;Los fire-trucks que hayan recibido un agree apagarán el fuego
  ask fire-trucks[
    if (apago_fuego = true) [
      face min-one-of fires [distance myself] ;; Face al fuego más cercano
      apagar_fuego ;;
      check-and-extinguish-fires
    ]
  ]
  if not any? fires [
    print "No hay fuegos por apagar."
  ]

end

to coordinated-one-min-distance

  ;El coordinador envía un mensaje request a los agentes
  if finished_messages = false [
    ask coordinadores [
      ask fire-trucks [

        send-message myself self "Request" "¿Cuál es mi distancia al fuego más cercano?";Envío mensaje Request de distancia, debe ser contestado con un inform
        process-messages
        ask myself [set requests1 lput myself requests1]
      ]
    ]
  ]

  ;Todo los agentes envian un Inform con su distancia mínima al coordinador
  ask fire-trucks [
    ask coordinadores [
      if  requests1 != [] [
        foreach requests1 [ elemento ->
          let dist 0
          ask elemento[set dist distance min-one-of fires [distance self]] ;Distancia en casillas
          let distKm dist * 0.666  ;Distancia en Km
          send-message elemento myself "Inform" (word "Distancia al fuego más cercano: " distKm " Km")  ;Envío mensaje Inform
          process-messages

          ;;Se añade la distancia al fuego más cercano a la lista de distancias del coordinador.
          if not member? (list dist elemento) distancesList ;si no está en lista lo añado
          [
            set distancesList lput (list dist elemento) distancesList

          ]  ; Añadir la distancia a la lista de distancias recibidas
        ]
      set requests1 []
      ]
    ]
  ]

  ;Todos los agentes envían un Request al coordinador para saber si van a apagar el fuego
  if finished_messages = false [
    ask fire-trucks [
      ask coordinadores [

        send-message myself self "Request" "¿APAGO EL FUEGO?";Envío mensaje Request acción. Debe ser contestado con un Agree o un Refuse
        process-messages
        set requests2 lput myself requests2
      ]
    ]
  ]

  ;El coordinador envía un Refuse a los fire-trucks que no deben apagar el fuego y un Agree a los que deben apagarlo
  if (finished_messages = false) [
    ask coordinadores [

      ;;SELECCIONO EL FIRETRUCK CON MEOR DISTANCIA MINIMA A FUEGOS
      let min_dist min item 0 distanceslist
      foreach distanceslist [element ->
        let primer_elemento item 0 element
        if (primer_elemento = min_dist)[
          let elegido item 1 element
          ask fire-trucks [
            if self = elegido[set apago_fuego true]
          ]
        ]
      ]

      ask fire-trucks[
        if (apago_fuego = true)[
          calculate-closest-fire-distance
          send-message myself self "Agree" (word "Action: Apagar fuego. Condition: Soy el fire-truck más próximo a fuego ")  ;Envío mensaje Agree
          process-messages

        ]
        if (apago_fuego = false) [
          send-message myself self "Refuse" (word "Action: No Apagar fuego. Reason: No soy el fire-truck más cercano ")  ;Envío mensaje Refuse
          process-messages
        ]
      set finished_messages true
      ]
    ]
  ]
  ;Los fire-trucks que hayan recibido un agree apagarán el fuego
  ask fire-trucks[
    if (apago_fuego = true) [
      face min-one-of fires [distance myself] ;; Face al fuego más cercano
      apagar_fuego
      check-and-extinguish-fires
    ]
  ]
  if not any? fires [
    print "No hay fuegos por apagar."
  ]

end

to proposal-one-min-distance

  ;El coordinador envía un mensaje call for proposal a los agentes
  if finished_messages = false [
    ask coordinadores [
      ask fire-trucks [

        send-message myself self "Call_for_proposal" "Action: Apagar Fuego. Precondition 1: Estar disponible, Precondition 2: Distancia mínima al fuego";Envío mensaje Request de distancia, debe ser contestado con un inform
        process-messages
        ask myself [set requests1 lput myself requests1]
      ]
    ]
  ]
  ;Todo los agentes envian un inform con su disponibilidad y distancia mínima al coordinady su disponibilidad
  ask fire-trucks [

    ask coordinadores [
      if  requests1 != [] [
        foreach requests1 [ elemento ->
          let dist 0
          ask elemento[
            set dist distance min-one-of fires [distance self] ;Esta es la distancia en casillas
            if apago_fuego = false [set disponible true]
          ]
          let distKm dist * 0.666  ;Distancia en Km
          send-message elemento myself "Inform" (word "Estoy disponible, Distancia al fuego más cercano: " distKm " Km")  ;Envío mensaje Inform
          process-messages

          ;;Cada firetruck añade a su lista las distancias mínimas del resto de firetrucks

          if not member? (list dist elemento) distancesList ;si no está en lista lo añado
          [
            set distancesList lput (list dist elemento) distancesList ; set distancesList lput (dist,who) distancesList
          ]  ; Añadir la distancia a la lista de distancias recibidas
        ]
      set requests1 []
      ]
    ]
  ]

  if (finished_messages = false) [
    ask coordinadores [
      ;;SELECCIONO EL FIRETRUCK CON MEOR DISTANCIA MINIMA A FUEGOS
      let min_dist_tuple first distanceslist


      foreach distanceslist [
        [element] ->
        if first element < first min_dist_tuple [
          set min_dist_tuple element
        ]
      ]
      let segundo_elemento item 1 min_dist_tuple

      ask fire-trucks [
        if self = segundo_elemento[
          set apago_fuego true
        ]
      ]

      ask fire-trucks[
        if(disponible = true and apago_fuego = true)[
          send-message myself self "Request" (word "Action: Apagar fuego. ")  ;Envío mensaje Request para que realice la acción apagar fuego (no espera respuesta es una orden)
          process-messages
          ask myself [set requests2 lput self requests2]
        ]
      ]
    ]
      set finished_messages true
  ]

 ;Los fire-trucks que hayan recibido un agree apagarán el fuego y los que ya estaban apagando algún fuego también
  ask fire-trucks[
    if (disponible = true and apago_fuego = true) or (disponible = false) [
      face min-one-of fires [distance myself] ;; Face al fuego más cercano
      apagar_fuego ;;
      check-and-extinguish-fires
    ]
  ]
  if not any? fires [
    print "No hay fuegos por apagar."
  ]

end

to distributed-attack
  let foco list 0 0
  let index 0
  let asignacion_fuegos [] ;Lista asigna a cada fire-truck su foco de incendio [Fire-truck X, [foco_posx, foco_posy]]
  if finished_messages = false [
    ask coordinadores[
      ask fire-trucks[
        set foco item index focos_incendio
        set asignacion_fuegos lput (list self foco) asignacion_fuegos ;Lista con fire-truck y foco asignado
        send-message myself self "Request" (word "Action: Apagar fuego: "index)  ;Envío mensaje Request para que realice la acción apagar fuego (no espera respuesta es una orden)
        process-messages
        set index index + 1
        if index = length focos_incendio [set index 0]
      ]
    ]
    set finished_messages true
  ]

  ;Envío a cada fire-truck al foco de incendio que le corresponde
  ask fire-trucks[
    foreach asignacion_fuegos[ [elemento]->
      if item 0 elemento = self[
        let foco_xy (item 1 elemento)
        set target-x item 0 foco_xy
        set target-y item 1 foco_xy
      ]
    ]
  ]
  ask fire-trucks[
    let x target-x
    let y target-y
    let target-fire min-one-of fires [
      distancexy x y
    ]
    if any? fires [
      face target-fire
      apagar_fuego
      check-and-extinguish-fires
    ]
  ]
  if not any? fires [
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
    let coslope cos(subtract-headings heading (- 180))
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
    let Cx ((RoS * sin(heading)) * (f2-2) * (1 + density-mod * d1) + windX * (1.05 - f2-2) * windmod + (s1 * slope / 100 * sin(- 180)))
    let Cy ((RoS * cos(heading)) * (f2-2) * (1 + density-mod * d1) + windY * (1.05 - f2-2) * windmod + (s1 * slope / 100 * cos( - 180)))
    ;print("SLOPE: ")
    ;print(slope)

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

 ;;;;;;;;;;;; Pre-heating
 ;;Si no hay patch-ahead quiere decir que se encuentra en un extremo del mapa y por lo tanto el siguiete patch no existe, entonces muere
    if (patch-ahead 1 != nobody) [
      ask patch-ahead 1 [
        ;print("FUEL: ")
        ;print(fuel)
        ;print("FLAM: ")
        ;print(flam)

        if flam < 1 [
          set flam flam + (0.005 * [RoS] of myself) / (1 + distance myself) ^ 2
        ]
      ]
    ] if fuera_mapa = true [
      die
    ]
     check-cell
    ]
end

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

;Copyright 2024 Adriano Miranda
@#$#@#$#@
GRAPHICS-WINDOW
449
10
1357
985
-1
-1
2.8938906752411575
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
310
0
333
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
186
179
219
wind-speed
wind-speed
0.01
50
15.01
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
1440.0
1
0
Number

SLIDER
7
220
179
253
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
87
464
210
509
Area Quemada (ha)
area
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

CHOOSER
210
64
336
109
Visualisation
Visualisation
"Fueltype" "Slope" "Flammability" "Fuel"
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
246
543
439
603
folder-name
Tijuana
1
0
String

BUTTON
246
603
439
636
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
249
518
436
562
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
0.8
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
417
235
Estrategy
Estrategy
"ALL_MIN_DIST" "ONE_MIN_DIST" "COORD_ONE_MIN_DIST" "PROP_ONE_MIN_DIST" "DISTRIBUTED_ATTACK"
4

SLIDER
207
271
379
304
Delay
Delay
0
10
3.0
1
1
NIL
HORIZONTAL

TEXTBOX
12
527
162
545
Ignition using coordinates
10
0.0
1

INPUTBOX
8
544
120
604
UTM-X
97000
1
0
String

INPUTBOX
120
544
241
604
UTM-Y
4690545
1
0
String

BUTTON
8
603
241
636
Ignition
geoCoords-ascCoords
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

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
