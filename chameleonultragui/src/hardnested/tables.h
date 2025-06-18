/*
 * To change this license header, choose License Headers in Project Properties.
 * To change this template file, choose Tools | Templates
 * and open the template in the editor.
 */

/*
 * File:   tables.h
 * Author: vk496
 *
 * Created on 15 de noviembre de 2018, 17:42
 */

#ifndef TABLES_H
#define TABLES_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include "../pm3/ui.h"
#include "../hardnested.h"

typedef struct bitflip_info
{
    uint32_t len;
    uint8_t *input_buffer;
} bitflip_info;

bitflip_info get_bitflip(odd_even_t odd_num, uint16_t id);

#endif /* TABLES_H */
