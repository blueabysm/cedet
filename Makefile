## Makefile --- Definition file for building CEDET
##
## Copyright (C) 2003 by David Ponce
##
## Author: David Ponce <david@dponce.com>
## Maintainer: CEDET developers <http://sf.net/projects/cedet>
## Created: 12 Sep 2003
## X-RCS: $Id: Makefile,v 1.1 2003-09-16 12:40:42 ponced Exp $
##
## This program is free software; you can redistribute it and/or
## modify it under the terms of the GNU General Public License as
## published by the Free Software Foundation; either version 2, or
## (at your option) any later version.
##
## This program is distributed in the hope that it will be useful, but
## WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with GNU Emacs; see the file COPYING.  If not, write to the
## Free Software Foundation, Inc., 59 Temple Place - Suite 330,
## Boston, MA 02111-1307, USA.

######## You can customize this part of the Makefile ########

## The directory where CEDET is installed
CEDET_HOME=$(CURDIR)

## The CEDET's packages installed
CEDET_PACKAGES=\
ede \
speedbar \
eieio \
semantic \
cogre

## The autoloads files of CEDET's packages

## It would be nice if autoloads files obey to the same naming
## convention. For example: <package-name>-loaddefs.el.  Thus, it
## would be possible to guess CEDET_LOADDEFS like this:
## CEDET_LOADDEFS=$(patsubst %,%-loaddefs.el,$(CEDET_PACKAGES))

CEDET_LOADDEFS=\
ede-loaddefs.el \
speedbar-defs.el \
eieio-defs.el \
semantic-al.el \
cogre-defs.el

## Path to your Emacs
EMACS=emacs

## Your shell (On Windows/Cygwin I recommend to use bash)
#SHELL=bash

## Path to your find and rm commands
FIND=find
#RM = rm -f

############### Internal part of the Makefile ###############
DOMAKE=$(MAKE) $(MFLAGS) EMACS="$(EMACS)" SHELL="$(SHELL)"

## Build
##

all: $(CEDET_PACKAGES)

.PHONY: $(CEDET_PACKAGES)
$(CEDET_PACKAGES):
	cd $(CEDET_HOME)/$@ && $(DOMAKE)

## Update
##

autoloads: $(patsubst %,%-autoloads,$(CEDET_PACKAGES))

.PHONY: %-autoloads
%-autoloads:
	cd $(CEDET_HOME)/$(firstword $(subst -, ,$@)) && \
	$(DOMAKE) autoloads

recompile: autoloads
	cd $(CEDET_HOME) && \
	$(EMACS) -batch -q --no-site-file -l common/cedet.el \
	-f batch-byte-recompile-directory $(CEDET_PACKAGES)

## Cleanup
##

clean-autoloads: $(patsubst %,clean-%,$(CEDET_LOADDEFS))

.PHONY: clean-%.el
clean-%.el:
	$(RM) $(CEDET_HOME)/$(word 2,$(subst -, ,$@))/$(subst clean-,,$@)

.PHONY: clean-grammars
clean-grammars:
	$(FIND) $(CEDET_HOME) -type f -name "*-[bw]y.el" \
	! -name "semantic-grammar-wy.el" \
	-print -exec $(RM) {} \;

.PHONY: clean-info
clean-info:
	$(FIND) $(CEDET_HOME) -type f -name "*.info*" \
	-print -exec $(RM) {} \;

.PHONY: clean-elc
clean-elc:
	$(FIND) $(CEDET_HOME) -type f -name "*.elc" \
	-print -exec $(RM) {} \;

.PHONY: clean
clean:
	$(FIND) $(CEDET_HOME) -type f \( -name "*-script" -o -name "*~" \) \
	-print -exec $(RM) {} \;

clean-all: clean clean-elc clean-info clean-grammars clean-autoloads

# Makefile ends here
