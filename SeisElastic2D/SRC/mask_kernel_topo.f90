program mask_kernel_topo
    ! To mask kernels with topography

#ifdef USE_MPI
    use mpi
#endif

    use seismo_parameters
    implicit none

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1
    integer, parameter :: NARGS = 3
    INTEGER :: itime, ier, isrc,i,j
    character(len=MAX_STRING_LEN) :: kernel_names(MAX_KERNEL_NUM)
    character(len=MAX_STRING_LEN) :: kernel_names_comma_delimited
    integer :: iker
    real(kind=CUSTOM_REAL), dimension(:,:,:,:),allocatable :: dat
    real(kind=CUSTOM_REAL), dimension(:,:,:,:),allocatable :: sum_dat
    real(kind=CUSTOM_REAL), dimension(:,:,:,:),allocatable :: mask_topo_fc ! PWY
    character(len=MAX_STRING_LEN) :: arg(NARGS)
    character(len=MAX_STRING_LEN) :: input_dir,output_dir
    character(len=MAX_FILENAME_LEN) :: filename
    character, parameter :: delimiter=','
    real t1,t2

#ifdef USE_MPI
    call MPI_INIT(ier)
    call MPI_COMM_SIZE(MPI_COMM_WORLD,nproc,ier)
    call MPI_COMM_RANK(MPI_COMM_WORLD,myrank,ier)
#else
    nproc = 1
    myrank = 0
#endif

    if (DISPLAY_DETAILS .and. myrank == 0) &
        print *,"Running mask_kernel_topo.exe on",NPROC,"processors"
    call cpu_time(t1)

    ! parse command line arguments
    if (command_argument_count() /= NARGS) then
        if (myrank == 0) then
            print *, 'USAGE:  mpirun -np NPROC bin/mask_kernel_topo.exe ...'
            stop ' Please check command line arguments'
        endif
    endif

#ifdef USE_MPI
    call MPI_BARRIER(MPI_COMM_WORLD,ier)
#endif

    do i = 1, NARGS
    call get_command_argument(i,arg(i), status=ier)
    enddo

    kernel_names_comma_delimited = arg(1)
    input_dir=arg(2)
    output_dir=arg(3)

    call split_string(kernel_names_comma_delimited,delimiter,kernel_names,nker)

    !! initialization  -- get number of spectral elements
    call initialize(output_dir) 

    !! allocation 
    allocate(dat(NGLLX,NGLLY,NGLLZ,NSPEC))
    allocate(sum_dat(NGLLX,NGLLY,NGLLZ,NSPEC))
    allocate(mask(NGLLX,NGLLY,NGLLZ,NSPEC))
    allocate(mask_topo_fc(NGLLX,NGLLY,NGLLZ,NSPEC))
    sum_dat = 0.0_CUSTOM_REAL
    dat = 0.0_CUSTOM_REAL
    mask = 1.0
    mask_topo_fc = 1.0

    ! loop over kernel
    do iker= 1, nker
    if(len(trim(adjustl(kernel_names(iker))))>0) then !non-empty
        !! kernel file
        write(filename,'(a,i6.6,a)') &
            trim(output_dir)//'/misfit_kernel/proc',myrank,&
            '_'//trim(adjustl(kernel_names(iker)))//'_smooth.bin'
        if (DISPLAY_DETAILS .and. myrank == 0 .and. isrc==0) &
            print*,'LOAD event_kernel --', trim(adjustl(kernel_names(iker)))
        ! gets slice of kernel
        open(unit=IIN,file=trim(filename),status='old',action='read',form='unformatted',iostat=ier)
        if (ier /= 0) then
            print *,'Error: could not open kernel file: ',trim(filename)
            stop 'Error reading neighbors external mesh file'
        endif
        ! global point arrays
        read(IIN) sum_dat
        close(IIN)

    if(DISPLAY_DETAILS .and. myrank==0 .and. isrc==0) &
        print *,' Min / Max = ',&
        minval(dat(:,:,:,:)),maxval(dat(:,:,:,:))

        ! read topography mask function
        write(filename,'(a,i6.6,a,i6.6,a)') &
            trim(input_dir)//'/000000/'//'/DATA/'//'/proc',&
            myrank,'_mask_topo.bin'
        open(unit=IIN,file=trim(filename),status='old',action='read',form='unformatted',iostat=ier)
        if (ier /= 0) then
            print *,'Error: could not open kernel file: ',trim(filename)
            stop 'Error reading neighbors external mesh file'
        endif
        read(IIN) mask_topo_fc
        close(IIN)
        if (myrank == 0 .and. isrc==0 .and. iker==0)  &
            print*,'LOAD topo mask file -- ',trim(filename)
 
        ! do topography mask
        sum_dat = sum_dat * mask_topo_fc
       
        !! SAVE masked kernel
        write(filename,'(a,i6.6,a)') &
            trim(output_dir)//'/misfit_kernel/proc',myrank,&
            '_'//trim(adjustl(kernel_names(iker)))//'_smooth.bin'
        if (myrank == 0) &
            print*,'SAVE misfit_kernel -- ',trim(adjustl(kernel_names(iker)))
        open(unit=IOUT,file=trim(filename),status='unknown',form='unformatted',iostat=ier)
        if (ier /= 0) then
            print*, 'Error: could not open gradient file: ',trim(filename)
            stop 'Error reading neighbors external mesh file'
        endif
        write(IOUT) sum_dat
        close(IOUT)

        if(DISPLAY_DETAILS .and. myrank==0) &
            print *,' Min / Max = ',&
                minval(sum_dat(:,:,:,:)),maxval(sum_dat(:,:,:,:))

    endif ! non-empty
    enddo !iker

    !! finalize
    deallocate(dat)
    deallocate(sum_dat) 
    deallocate(mask)
    deallocate(mask_topo_fc)

    call cpu_time(t2)

    if (DISPLAY_DETAILS .and. myrank == 0)  print *,'Computation time with CPU:',t2-t1

#ifdef USE_MPI
    ! stop all the processes and exit
    call MPI_FINALIZE(ier)
#endif

end program mask_kernel_topo
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
subroutine initialize(directory)
    use seismo_parameters
    implicit none
    integer :: ier
    character(len=MAX_FILENAME_LEN) :: filename
    character(len=MAX_STRING_LEN) :: directory

    write(filename,'(a,i6.6,a)') &
        trim(directory)//'/misfit_kernel/proc',myrank,'_'//trim(IBOOL_NAME)

    open(IIN,file=trim(filename),status='old',action='read',form='unformatted',iostat=ier)
    if (ier /= 0) then
        print *,'Error: could not open database file: ',trim(filename)
        stop 'Error opening _NSPEC_IBOOL file'
    endif
    read(IIN) nspec
    close(IIN)
    if(DISPLAY_DETAILS .and. myrank==0) print*,'number of elements : ',nspec

end subroutine initialize
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
