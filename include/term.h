#ifndef TERM_H
#define TERM_H

#include <curses.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct term TERMINAL;
extern TERMINAL *cur_term;

int setupterm(const char *term, int filedes, int *errret);
int del_curterm(TERMINAL *oterm);
char *tigetstr(const char *capname);
int tigetnum(const char *capname);
int tigetflag(const char *capname);
char *tparm(const char *str, ...);

#ifdef __cplusplus
}
#endif

#endif /* TERM_H */
