# Wiki del Driver FL2000 DRM para Linux Kernel 6.x

## Tabla de Contenidos

1. [Introducción](#introducción)
2. [Arquitectura del Driver](#arquitectura-del-driver)
3. [Compatibilidad con Kernel](#compatibilidad-con-kernel)
4. [Instalación Detallada](#instalación-detallada)
5. [Secure Boot](#secure-boot)
6. [Configuración y Uso](#configuración-y-uso)
7. [Resolución de Problemas](#resolución-de-problemas)
8. [Desarrollo y Contribución](#desarrollo-y-contribución)
9. [FAQ](#faq)

---

## Introducción

### ¿Qué es el FL2000?

El FL2000 es un chip USB a HDMI de Fresco Logic que permite agregar un monitor HDMI adicional a través de un puerto USB. Estos adaptadores son常见的 (common) en marketplaces como Amazon, AliExpress, eBay.

### Características del Driver

- ** DRM moderno**: Implementación usando las APIs más recientes del kernel 6.x
- ** Soporte completo**: Incluye driver para el puente HDMI IT66121FN
- ** Atomic modesetting**: Soporte completo para atomic (el método moderno de configuración de pantalla)
- ** Plug & Play**: Detección automática del dispositivo
- ** Resolución adaptativa**: Ajusta automáticamente la resolución basada en el ancho de banda USB disponible

---

## Arquitectura del Driver

### Componentes Principales

```
┌─────────────────────────────────────────────────────────────┐
│                    FL2000 USB Driver                        │
├─────────────────────────────────────────────────────────────┤
│  fl2000_drv.c                                               │
│  ├── Registro de dispositivo USB                           │
│  ├── Inicialización de componentes DRM                     │
│  └── Gestión de energía (suspend/resume)                   │
├─────────────────────────────────────────────────────────────┤
│  fl2000_drm.c                                               │
│  ├── Configuración del pipeline de display                 │
│  ├── Cálculo de timing y PLL                               │
│  ├── Gestión de framebuffer                                │
│  └── Modos de pantalla (DRM modesetting)                  │
├─────────────────────────────────────────────────────────────┤
│  fl2000_streaming.c                                         │
│  ├── Transferencias USB isoc/bulk                          │
│  ├── Compresión de datos de imagen                        │
│  └── Buffer management (triple-buffering)                  │
├─────────────────────────────────────────────────────────────┤
│  fl2000_i2c.c                                               │
│  ├── Interfaz I2C hacia el puente IT66121                 │
│  └── Comunicación con registros del chip                   │
├─────────────────────────────────────────────────────────────┤
│  bridge/it66121.c                                           │
│  ├── Driver del puente HDMI                                │
│  ├── Lectura de EDID                                       │
│  ├── Configuración de Timing HDMI                          │
│  └── Gestión de hotplug                                    │
└─────────────────────────────────────────────────────────────┘
```

### Flujo de Datos

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│  Xorg/   │───▶│  DRM     │───▶│  Plane   │───▶│  FL2000  │───▶│  USB     │
│  Wayland │    │  Core    │    │  (FB)    │    │  Chip    │    │  Bus     │
└──────────┘    └──────────┘    └──────────┘    └──────────┘    └──────────┘
                    │                                         │
                    ▼                                         ▼
              ┌──────────┐                              ┌──────────┐
              │ IT66121  │◀─────────────────────────────│  Monitor │
              │  Bridge  │        HDMI                 │   HDMI   │
              └──────────┘                              └──────────┘
```

---

## Compatibilidad con Kernel

### Requisitos

| Componente | Requisito |
|------------|-----------|
| Kernel Linux | 6.x (probado hasta 6.17) |
| Arquitectura | x86_64 |
| DRM | drm, drm_kms_helper |
| USB | usbcore, ehci-hcd / xhci-hcd |
| build-essential | GCC 8+, make, linux-headers |

### APIs DRM Utilizadas

El driver ha sido actualizado para usar las siguientes APIs modernas del kernel 6.x:

- **DRM Core**: `drm_device`, `drm_driver`, `drm_file`
- **GEM**: `drm_gem_dma_driver`, memoria con mapeo DMA
- **Atomic Helpers**: `drm_atomic_helper_*`
- **Mode Config**: `drmm_mode_config_init`, `drm_simple_display_pipe`
- **Framebuffers**: `drm_gem_fb_create_with_dirty`
- **Planes**: `drm_plane_enable_fb_damage_clips`
- **Client API**: `drm_client_*`

### Cambios Realizados para Kernel 6.x

1. **Headers actualizados**: Eliminados headers deprecated
2. **Postclose**: Cambiado de `lastclose` a `postclose` para manejo de cierre
3. **Bridge API**: Actualizada firma de `attach` para incluir encoder
4. **EDID**: Cambiado a usar `drm_get_edid` con i2c_adapter
5. **HPD**: Cambiado de `drm_helper_hpd_irq_event` a `drm_bridge_hpd_notify`

---

## Instalación Detallada

### Paso 1: Preparar el Entorno

```bash
# Instalar dependencias (Debian/Ubuntu)
sudo apt-get update
sudo apt-get install build-essential linux-headers-$(uname -r)

# Verificar versión del kernel
uname -r
# Output esperado: 6.17.0-23-generic (o similar 6.x)
```

### Paso 2: Clonar o Descargar el Driver

```bash
# Si tienes el código fuente
cd /home/samuel/driver/fl2000_drm

# Verificar estructura
ls -la
```

### Paso 3: Compilar

```bash
# Limpiar compilaciones anteriores
make clean

# Compilar para tu kernel
make KVER=$(uname -r)

# Verificar que se crearon los módulos
ls -la *.ko
```

### Paso 4: Instalar

```bash
# Opción A: Usar el script automático
sudo ./install.sh

# Opción B: Instalar manualmente
MODULE_DIR="/lib/modules/$(uname -r)/extra"
sudo mkdir -p "$MODULE_DIR"
sudo cp fl2000.ko it66121.ko "$MODULE_DIR/"
sudo depmod -a
```

---

## Secure Boot

### Entendiendo Secure Boot

Secure Boot es una característica de UEFI que verifica que todo el código cargado durante el inicio esté firmado digitalmente por una autoridad confiable. Esto incluye los módulos del kernel.

### Proceso de Firma

#### Paso 1: Verificar el Estado de Secure Boot

```bash
# Verificar si está habilitado
mokutil --sb-state

# Salida típica si está habilitado:
# SecureBoot enabled

# Salida si está deshabilitado:
# SecureBoot disabled
```

#### Paso 2: Generar Claves de Firma (Primera vez)

```bash
# Crear directorio para claves si no existe
sudo mkdir -p /var/lib/dkms

# Generar clave RSA 2048 bits
sudo openssl req -new -x509 -newkey rsa:2048 \
    -keyout /var/lib/dkms/mok.key \
    -out /var/lib/dkms/mok.pub \
    -days 3650 -nodes \
    -subj "/CN=FL2000 Driver Signing Key/"

# Proteger la clave privada
sudo chmod 600 /var/lib/dkms/mok.key
sudo chmod 644 /var/lib/dkms/mok.pub
```

#### Paso 3: Firmar los Módulos

```bash
# Firmar fl2000.ko
sudo /usr/bin/sign-file sha256 \
    /var/lib/dkms/mok.key \
    /var/lib/dkms/mok.pub \
    /lib/modules/$(uname -r)/extra/fl2000.ko

# Firmar it66121.ko
sudo /usr/bin/sign-file sha256 \
    /var/lib/dkms/mok.key \
    /var/lib/dkms/mok.pub \
    /lib/modules/$(uname -r)/extra/it66121.ko
```

#### Paso 4: Registrar la Clave en MOK

```bash
# Importar la clave pública al sistema MOK
sudo mokutil --import /var/lib/dkms/mok.pub

# Este comando pedirà una contraseña temporal
# You'll need to reboot and follow the MOK enrollment prompt
```

#### Paso 5: Reiniciar y Completar MOK Enrollment

1. Reinicia tu sistema
2. Durante el inicio, verás el menú de MOK (Machine Owner Key)
3. Selecciona "Enroll MOK Key"
4. Completa el proceso de enrollment
5. El sistema continuará iniciando

### Script Automático de Instalación

El script `install.sh` incluido maneja automáticamente todo este proceso:

```bash
sudo ./install.sh
```

El script:
1. Compila el driver
2. Detecta el estado de Secure Boot
3. Genera claves si no existen
4. Firma los módulos
5. Registra la clave MOK si es necesario

---

## Configuración y Uso

### Cargar el Driver

```bash
# Cargar manualmente
sudo modprobe fl2000

# Verificar carga
lsmod | grep fl2000

# Ver mensajes del driver
dmesg | grep -i fl2000
```

### Verificar el Dispositivo

```bash
# Listar dispositivos USB conectados
lsusb | grep -i fresco
# Salida típica: 1d5c:2000 Fresco Logic, Inc. FL2000 USB Display

# Ver dispositivos DRM
ls -la /dev/dri/
# Output típico: card0, card1, renderD128

# Información detallada
cat /sys/class/drm/*/device/name
```

### Configurar la Pantalla

#### Usando xrandr (X11)

```bash
# Listar salidas disponibles
xrandr --listmonitors

# Activar monitor externo
xrandr --output <output-name> --auto

# Establecer resolución específica
xrandr --output <output-name> --mode 1920x1080
```

#### Usando Wayland

Los entornos GNOME, KDE y otros detectan automáticamente el nuevo monitor a través de DRM.

#### Usando DRM directamente

```bash
# Ver información de conectores
cat /sys/class/drm/card1-*/status
# Output: connected o disconnected

# Forzar detección
cat /sys/class/drm/card1-*/dpms
```

### Parámetros del Módulo (Opcional)

El driver actualmente no tiene parámetros configurables en tiempo de carga, pero puedes verificar los parámetros del sistema:

```bash
# Ver parámetros actuales (si existen)
cat /sys/module/fl2000/parameters/*
```

### Configuración de Resolución Automática

El driver calcula automáticamente la mejor resolución basada en:

1. **Capacidad del monitor** (lectura de EDID)
2. **Ancho de banda USB**:
   - USB 2.0: Hasta ~40MB/s → 1080p@30Hz máximo
   - USB 3.0: Hasta ~400MB/s → 1080p@60Hz o 4K@30Hz

---

## Resolución de Problemas

### El driver no carga

#### Síntomas
```bash
$ sudo modprobe fl2000
modprobe: ERROR: could not insert 'fl2000': Operation not permitted
```

#### Solución
1. Verificar que estás ejecutando como root o con sudo
2. Verificar que Secure Boot no esté bloqueando el módulo

#### Verificar errores
```bash
dmesg | tail -20
```

### Error de compilación

#### Síntomas
```
make: *** No rule to make target 'modules'
```

#### Solución
```bash
# Instalar headers del kernel
sudo apt-get install linux-headers-$(uname -r)

# Verificar que existen
ls /lib/modules/$(uname -r)/build
```

### El dispositivo se detecta pero no hay imagen

#### Síntomas
- `lsusb` muestra el dispositivo
- `dmesg` muestra que el driver se cargó
- No hay imagen en el monitor

#### Solución
1. Verificar cable HDMI
2. Probar con otro monitor
3. Verificar que el IT66121 se detecta:
   ```bash
   dmesg | grep it66121
   ```
4. Revisar resoluciones soportadas:
   ```bash
   xrandr
   ```

### Conflictos con otros drivers

#### Síntomas
```
fl2000: probe of 1-1:1.0 failed with error -16
```

#### Solución
```bash
# Desinstalar otros drivers que puedan conflicted
sudo rmmod <conflicting-module>

#-blacklist en /etc/modprobe.d/
echo "blacklist <module>" | sudo tee /etc/modprobe.d/blacklist.conf
```

### Problemas con休眠 (Suspend)

#### Síntomas
El monitor no wakes up después de suspender el sistema

#### Solución
```bash
# Verificar soporte de runtime PM
cat /sys/bus/usb/devices/1-1:1.0/power/control

# Forzar siempre-on
echo "on" | sudo tee /sys/bus/usb/devices/1-1:1.0/power/control
```

---

## Desarrollo y Contribución

### Estructura del Código

```
fl2000_drm/
├── fl2000.h              # Definiciones públicas
├── fl2000_drv.c          # Driver USB principal
├── fl2000_drm.c          # Implementación DRM
├── fl2000_drm.h          # Definiciones internas DRM
├── fl2000_streaming.c    # Streaming de datos
├── fl2000_i2c.c          # Comunicación I2C
├── fl2000_interrupt.c    # Manejo de interrupciones
├── fl2000_registers.c   # Acceso a registros
├── bridge/
│   ├── it66121.h         # Definiciones del puente
│   ├── it66121_drv.c     # Driver del puente
│   └── it66121_registers.h
├── Makefile
├── install.sh            # Script de instalación
└── README.md
```

### Estilo de Código

El driver sigue las convenciones del kernel de Linux:

- **Indentación**: 8 espacios (tabs)
- **Nombrado**: snake_case para variables, PascalCase para funciones
- **Documentación**: Estilo Doxygen/kernel para comentarios

### Compilación con debugging

```bash
# Agregar símbolos de debug
make KVER=$(uname -r) EXTRA_CFLAGS="-g -DDEBUG"
```

### Testing

```bash
# Verificar que los símbolos se cargan correctamente
sudo modprobe -v fl2000

# Monitoring de errores
sudo dmesg -w | grep -E "fl2000|it66121|drm"

# Verificar memoria
cat /proc/modules | grep fl2000
```

---

## FAQ

### ¿Funcionará con mi adaptador específico?

El driver es compatible con cualquier adaptador USB-HDMI basado en:
- FL2000 (Fresco Logic)
- IT66121 (ITE Tech) como puente HDMI

Puedes verificar el chip de tu adaptador:
```bash
lsusb
# Busca: 1d5c:2000
```

### ¿Por qué la resolución es limitada?

La resolución máxima está limitada por el ancho de banda USB:
- USB 2.0: ~480 Mbps → ~40 MB/s efectivos
- USB 3.0: ~5 Gbps → ~400 MB/s efectivos

El driver automáticamente selecciona la mejor resolución posible.

### ¿Puedo usar múltiples monitores FL2000?

Técnicamente es posible pero no ha sido probado extensivamente. Cada adaptador requiere su propio bus USB con suficiente ancho de banda.

### ¿El driver soporta audio HDMI?

El código IT66121 tiene soporte para audio, pero está deshabilitado actualmente por simplicidad. La funcionalidad de audio se puede añadir en futuras versiones.

### ¿Funciona con Wayland?

Sí. Wayland usa DRM/KMS directamente, por lo que el driver funciona automáticamente con GNOME, KDE, Sway, y otrosCompositors de Wayland.

### ¿Funciona con X11?

Sí. X11 usa el driver DRM a través deModesetting DDX. La aceleración 3D no está disponible (no es necesaria para escritorio básico).

### ¿Puedo usar el driver en un sistema con Secure Boot?

Sí, el script de instalación maneja automáticamente la firma de los módulos para Secure Boot.

### ¿El driver funciona después de actualizar el kernel?

Sí, pero necesitarás recompilar el driver después de cada actualización del kernel:

```bash
# Después de actualizar el kernel
sudo ./install.sh
```

---

## Referencias

- [Repositorio Original](https://github.com/klogg/fl2000_drm)
- [Documentación DRM del Kernel](https://www.kernel.org/doc/html/latest/gpu/drm-kms-helpers.html)
- [Especificación FL2000](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/ast/ast_drm.c)
- [Wiki de DRM](https://wiki.freedesktop.org/title/DRM)

---

*Última actualización: Mayo 2026*
*Driver compatible con Kernel 6.17+*