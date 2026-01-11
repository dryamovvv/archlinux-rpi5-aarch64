  GNU nano 7.2                            lib/logger.sh                                      
#!/bin/bash
# lib/template.sh

# Защита от повторного импорта
[[ -n "$_LIB_LOGGER_LOADED" ]] && return || readonly _LIB_LOGGER_LOADED=1
