FROM ubuntu:jammy

WORKDIR /block

COPY . /block

RUN apt update && apt install -y cc65 cc65-doc vim-tiny openjdk-11-jdk make
