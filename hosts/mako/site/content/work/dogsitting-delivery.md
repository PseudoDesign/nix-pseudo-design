+++
title = "A small stateful service, packaged end to end"
description = "A small private checklist application packaged from local development through a security-conscious NixOS production service."
date = 2026-05-21
draft = false
template = "case-study.html"

[extra]
order = 3
deliverable = "Private checklist application and NixOS service"
repository_url = "https://github.com/PseudoDesign/dogsitting"
external_url = ""
+++

## Problem

A private dogsitting checklist needs a web interface that is small enough to operate directly while still having a reproducible path from development to an HTTPS deployment.

## Constraints

Application state remains local to the service, and the initial administrator password arrives through a host-managed file rather than source configuration. Production traffic must pass through a reverse proxy while the application itself remains bound to localhost.

## Investigation

Development, administrator initialization, serving, and host integration were treated as parts of one delivery surface. The standalone flake keeps the application package, test environment, command-line entry points, and NixOS service module together instead of leaving production assembly to a separate repository.

## Delivered System

The repository provides the checklist web application, a Python unit-test workflow, commands to initialize an administrator and run the server, and a reusable NixOS module. Its production profile configures nginx as the HTTPS reverse proxy and enables secure cookies, trusted proxy headers, rate limits, and strict security headers.

## Demonstrated Result

The application can run locally from the flake against an explicit state directory, then be enabled on NixOS through `services.dogsitting`. The Pseudo Design host configuration consumes that flake as an input, supplies the administrator password by file, and publishes the service through its dedicated nginx virtual host.

## Handoff

The public README keeps the operational interface compact: enter the development environment, run the unit suite, initialize an administrator, serve locally, or enable the NixOS module. Host-specific state, credentials, port, and public hostname stay outside the application package.
